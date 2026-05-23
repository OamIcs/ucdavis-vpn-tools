#!/usr/bin/env node
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { homedir } from "node:os";

const args = new Set(process.argv.slice(2));
const jsonOutput = args.has("--json");
const noLogin = args.has("--no-login");
const forceLogin = args.has("--force-login");
const clearCookie = args.has("--clear-cookie");

const env = (name, fallback = "") => process.env[name] || fallback;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const server = env("UCD_VPN_SERVER", "vpn.engineering.ucdavis.edu");
const email = env("UCD_VPN_EMAIL", "");
const keychainService = env("UCD_VPN_KEYCHAIN_SERVICE", "ucdavis-openconnect-vpn");
const profileDir = env(
  "UCD_VPN_PROFILE_DIR",
  `${homedir()}/.local/state/ucdavis-vpn-chrome-profile`,
);
const chromeApp = env("UCD_VPN_CHROME_APP", "Google Chrome");
const cdpPort = Number(env("UCD_VPN_CDP_PORT", "9223"));
const loginTimeoutMs = Number(env("UCD_VPN_LOGIN_TIMEOUT_MS", "240000"));
const closeWindowAfterCookie = env("UCD_VPN_CLOSE_WINDOW_AFTER_COOKIE", "1") !== "0";
const loginUrl = env(
  "UCD_VPN_LOGIN_URL",
  `https://${server}/dana-na/auth/url_default/login.cgi?realm=Azure%20AD`,
);

let browserStarted = false;
let usedLogin = false;

const log = (message) => {
  console.error(`[vpn-cookie] ${message}`);
};

async function waitJson(url, timeoutMs = 15000) {
  const start = Date.now();
  let last = "";
  while (Date.now() - start < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.json();
      last = `${response.status} ${response.statusText}`;
    } catch (error) {
      last = error.message;
    }
    await sleep(250);
  }
  throw new Error(`Timed out waiting for ${url}: ${last}`);
}

async function cdpAvailable() {
  try {
    const response = await fetch(`http://127.0.0.1:${cdpPort}/json/version`);
    return response.ok;
  } catch {
    return false;
  }
}

async function ensureChrome() {
  mkdirSync(profileDir, { recursive: true });
  if (!(await cdpAvailable())) {
    browserStarted = true;
    log(`starting ${chromeApp} with persistent profile ${profileDir}`);
    spawnSync("/usr/bin/open", [
      "-na",
      chromeApp,
      "--args",
      `--user-data-dir=${profileDir}`,
      `--remote-debugging-port=${cdpPort}`,
      "--no-first-run",
      "--no-default-browser-check",
      "about:blank",
    ], { stdio: "ignore" });
  }

  await waitJson(`http://127.0.0.1:${cdpPort}/json/version`, 20000);
  let tabs = await waitJson(`http://127.0.0.1:${cdpPort}/json`, 20000);
  if (!tabs.some((tab) => tab.type === "page")) {
    await fetch(`http://127.0.0.1:${cdpPort}/json/new?about:blank`, {
      method: "PUT",
    }).catch(() => {});
    tabs = await waitJson(`http://127.0.0.1:${cdpPort}/json`, 5000);
  }
  const tab = tabs.find((candidate) => candidate.type === "page") || tabs[0];
  if (!tab?.webSocketDebuggerUrl) {
    throw new Error("Chrome DevTools page target was not available");
  }
  return {
    targetId: tab.id,
    webSocketDebuggerUrl: tab.webSocketDebuggerUrl,
  };
}

async function connectCdp(webSocketDebuggerUrl) {
  let id = 0;
  const pending = new Map();
  const ws = new WebSocket(webSocketDebuggerUrl);
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
    }
  });
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });
  });

  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const messageId = ++id;
    pending.set(messageId, { resolve, reject });
    ws.send(JSON.stringify({ id: messageId, method, params }));
  });

  return { ws, send };
}

async function evalPage(send, expression) {
  const output = await send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (output.exceptionDetails) {
    throw new Error(output.exceptionDetails.text || "page evaluation failed");
  }
  return output.result?.value;
}

async function closePageTarget(targetId) {
  if (!closeWindowAfterCookie || !targetId) return false;
  try {
    await fetch(`http://127.0.0.1:${cdpPort}/json/close/${targetId}`);
    log("closed visible Chrome login window; profile/session process is left running");
    return true;
  } catch (error) {
    log(`could not close Chrome login window: ${error.message}`);
    return false;
  }
}

function cookieExpirySummary(cookies) {
  return cookies
    .filter((cookie) => {
      const domain = cookie.domain.replace(/^\./, "").toLowerCase();
      return domain === server || domain.endsWith(`.${server}`);
    })
    .map((cookie) => ({
      name: cookie.name,
      session: Boolean(cookie.session),
      expiresAt: cookie.expires > 0 ? new Date(cookie.expires * 1000).toISOString() : "session",
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

function cookieFromList(cookies) {
  const wanted = cookies.filter((cookie) => {
    const domain = cookie.domain.replace(/^\./, "").toLowerCase();
    return domain === server || domain.endsWith(`.${server}`);
  });
  const byName = Object.fromEntries(wanted.map((cookie) => [cookie.name, cookie.value]));
  const names = wanted.map((cookie) => cookie.name).sort();

  if (!byName.DSID) return { cookie: "", names };

  const order = [
    "DSSignInURL",
    "DSSignInUrl",
    "DSID",
    "DSFirstAccess",
    "DSLastAccess",
    "DSSIGNIN",
    "DSPREAUTH",
    "DSDID",
  ];
  const parts = [];
  for (const name of order) {
    if (byName[name]) parts.push(`${name}=${byName[name]}`);
  }
  for (const cookie of wanted) {
    if (!order.includes(cookie.name) && /^DS/.test(cookie.name)) {
      parts.push(`${cookie.name}=${cookie.value}`);
    }
  }
  return { cookie: parts.join("; "), names };
}

async function getVpnCookie(send) {
  const data = await send("Network.getAllCookies");
  return {
    ...cookieFromList(data.cookies || []),
    expiries: cookieExpirySummary(data.cookies || []),
  };
}

async function clearVpnCookies(send) {
  const data = await send("Network.getAllCookies");
  const wanted = (data.cookies || []).filter((cookie) => {
    const domain = cookie.domain.replace(/^\./, "").toLowerCase();
    return domain === server || domain.endsWith(`.${server}`);
  });
  for (const cookie of wanted) {
    await send("Network.deleteCookies", {
      name: cookie.name,
      domain: cookie.domain,
      path: cookie.path || "/",
    }).catch(() => {});
  }
  return wanted.map((cookie) => cookie.name).sort();
}

async function pageState(send) {
  return await evalPage(send, `(() => {
    const visible = (element) => !!(element && (element.offsetWidth || element.offsetHeight || element.getClientRects().length));
    const label = (element) => (element.innerText || element.value || element.getAttribute("aria-label") || "").trim();
    return {
      href: location.href,
      host: location.hostname,
      title: document.title,
      readyState: document.readyState,
      emailVisible: [...document.querySelectorAll("input[type=email], input#i0116, input[name*=loginfmt], input[name*=email i]")].some(visible),
      passwordVisible: [...document.querySelectorAll("input[type=password], input#i0118")].some(visible),
      buttons: [...document.querySelectorAll("input[type=submit], button")].filter(visible).slice(0, 8).map(label),
      body: document.body ? document.body.innerText.slice(0, 800) : ""
    };
  })()`);
}

function readPassword() {
  if (!email) throw new Error("Set UCD_VPN_EMAIL before browser login");
  const fromEnv = env("UCD_VPN_PASSWORD");
  if (fromEnv) return fromEnv;
  return execFileSync("/usr/bin/security", [
    "find-generic-password",
    "-s",
    keychainService,
    "-a",
    email,
    "-w",
  ], { encoding: "utf8" }).replace(/[\r\n]+$/, "");
}

async function submitMicrosoftEmail(send) {
  if (!email) throw new Error("Set UCD_VPN_EMAIL before browser login");
  await evalPage(send, `(() => {
    const email = ${JSON.stringify(email)};
    const input = document.querySelector("input#i0116, input[name=loginfmt], input[type=email]");
    if (!input) return false;
    const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(input), "value") ||
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
    descriptor.set.call(input, email);
    input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: email }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    input.focus();
    const button = document.querySelector("#idSIButton9, input[type=submit], button[type=submit], button");
    if (button) button.click();
    return true;
  })()`);
}

async function submitSchoolPassword(send, password) {
  await evalPage(send, `(() => {
    const password = ${JSON.stringify(password)};
    const visible = (element) => !!(element && (element.offsetWidth || element.offsetHeight || element.getClientRects().length));
    const input = [...document.querySelectorAll("input[type=password], input#i0118")].find(visible);
    if (!input) return false;
    const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(input), "value") ||
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
    descriptor.set.call(input, password);
    input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: password }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    input.focus();
    const candidates = [...document.querySelectorAll("input[type=submit], button")].filter(visible);
    const button = candidates.find((element) => /sign|log|submit|continue|next/i.test(element.innerText || element.value || element.id || element.name || "")) || candidates[0];
    if (button) button.click();
    else if (input.form?.requestSubmit) input.form.requestSubmit();
    return true;
  })()`);
}

async function loginForCookie(send) {
  usedLogin = true;
  let submittedEmail = false;
  let submittedPassword = false;
  let password = "";

  log("opening VPN SAML login page");
  await send("Page.navigate", { url: loginUrl });

  const start = Date.now();
  let lastState = null;
  let lastCookieNames = [];
  while (Date.now() - start < loginTimeoutMs) {
    const cookie = await getVpnCookie(send);
    if (cookie.names.join(",") !== lastCookieNames.join(",")) {
      lastCookieNames = cookie.names;
      if (lastCookieNames.length) log(`VPN cookie names: ${lastCookieNames.join(", ")}`);
    }
    if (cookie.cookie) return cookie;

    lastState = await pageState(send);
    const body = lastState.body || "";
    if (/incorrect user id or password|incorrect|invalid password|type the correct user id or password/i.test(body)) {
      throw new Error(`login page reported an error: ${body.replace(/\s+/g, " ").slice(0, 220)}`);
    }

    if (!submittedEmail && lastState.host.includes("microsoftonline.com") && lastState.emailVisible) {
      log("submitting Microsoft email");
      await submitMicrosoftEmail(send);
      submittedEmail = true;
      await sleep(750);
      continue;
    }

    if (!submittedPassword && !lastState.host.includes("microsoftonline.com") && lastState.passwordVisible) {
      log("submitting UC Davis password");
      password ||= readPassword();
      await submitSchoolPassword(send, password);
      submittedPassword = true;
      await sleep(1000);
      continue;
    }

    await sleep(1000);
  }

  throw new Error(`timed out waiting for VPN cookie; last page was ${lastState?.host || "unknown"} / ${lastState?.title || "unknown"}`);
}

async function main() {
  const { targetId, webSocketDebuggerUrl } = await ensureChrome();
  const { ws, send } = await connectCdp(webSocketDebuggerUrl);

  try {
    await send("Page.enable");
    await send("Runtime.enable");
    await send("Network.enable");

    if (forceLogin || clearCookie) {
      const deleted = await clearVpnCookies(send);
      if (deleted.length) log(`cleared VPN cookie names: ${deleted.join(", ")}`);
    }

    let result = forceLogin ? { cookie: "", names: [] } : await getVpnCookie(send);
    if (!result.cookie && !noLogin) {
      result = await loginForCookie(send);
    }

    const output = {
      ok: Boolean(result.cookie),
      cookie: result.cookie,
      cookieNames: result.names,
      cookieExpiries: result.expiries || [],
      profileDir,
      cdpPort,
      server,
      usedLogin,
      browserStarted,
      closeWindowAfterCookie,
      checkedAt: new Date().toISOString(),
    };

    if (jsonOutput) {
      console.log(JSON.stringify(output));
    } else {
      console.log(output.ok ? "cookie: present" : "cookie: missing");
      console.log(`cookie names: ${output.cookieNames.join(", ") || "(none)"}`);
      console.log(`profile: ${profileDir}`);
      console.log(`chrome cdp: 127.0.0.1:${cdpPort}`);
    }
    if (output.ok || noLogin) await closePageTarget(targetId);
    ws.close();
    process.exit(output.ok ? 0 : 2);
  } catch (error) {
    ws.close();
    throw error;
  }
}

main().catch((error) => {
  console.error(`[vpn-cookie] ERROR: ${error.message}`);
  process.exit(1);
});
