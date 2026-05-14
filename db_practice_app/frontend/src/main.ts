import "./style.css";
import "./app.css";

import { Auth } from "../wailsjs/go/main/App";
import { initMap } from "./map";
import { authStore } from "./auth";

async function handleLogin(
  username: string,
  password: string,
): Promise<boolean> {
  const resEl = document.getElementById("result");
  if (resEl) resEl.innerText = "Authenticating...";

  try {
    const user = await Auth(username, password);
    authStore.setUser(user);
    return true;
  } catch (err) {
    if (resEl) {
      resEl.innerText = "Invalid credentials. Please try again.";
      resEl.style.color = "#ff4d4d";
    }
    return false;
  }
}

const renderLogin = () => {
  appElement.innerHTML = `
    <div class="auth-wrapper">
        <div class="auth-card">
            <h1>Logistics Pro</h1>
            <p>Authorized personnel only</p>
            
            <div class="auth-result" id="result"></div>
            
            <div class="input-group">
                <input class="auth-input" id="username" type="text" placeholder="Username" autocomplete="off" />
                <input class="auth-input" id="password" type="password" placeholder="Password" />
            </div>
            
            <button class="btn-login" id="loginBtn">Initialize Session</button>
        </div>
    </div>
  `;

  const loginBtn = document.getElementById("loginBtn") as HTMLButtonElement;
  const userIn = document.getElementById("username") as HTMLInputElement;
  const passIn = document.getElementById("password") as HTMLInputElement;
  const resEl = document.getElementById("result");

  userIn.focus();

  loginBtn?.addEventListener("click", async () => {
    const u = userIn.value.trim();
    const p = passIn.value;

    if (!u || !p) {
      if (resEl) resEl.innerText = "Credentials required.";
      return;
    }

    loginBtn.disabled = true;
    loginBtn.innerText = "Authenticating...";

    const success = await handleLogin(u, p);

    if (success) {
      renderDashboard();
    } else {
      loginBtn.disabled = false;
      loginBtn.innerText = "Initialize Session";
    }
  });

  passIn.addEventListener("keypress", (e) => {
    if (e.key === "Enter") {
      loginBtn?.click();
    }
  });
};

const renderDashboard = () => {
  const user = authStore.getUser()!;
  const canSeePeople =
    user.role_name === "Admin" || user.role_name === "Dispatcher";
  const canSeeFleet = user.role_name !== "Customer";

  appElement.innerHTML = `
    <div class="dashboard-layout">
        <nav class="sidebar">
            <h2>Logistics Pro</h2>
            <div class="user-badge">
                <p>${user.username}</p>
                <span class="role-tag">${user.role_name}</span>
            </div>
            <ul class="nav-list">
                <li><button class="nav-btn active" id="nav-map">🗺️ Infrastructure Map</button></li>
                ${canSeePeople ? `<li><button class="nav-btn" id="nav-people">👥 People & Staff</button></li>` : ""}
                ${canSeeFleet ? `<li><button class="nav-btn" id="nav-fleet">🚗 Fleet Status</button></li>` : ""}
            </ul>
            <button class="btn-logout" id="logoutBtn">Logout</button>
        </nav>
        <main class="content-area">
            <div class="header-bar">
                <h1 id="view-title">Command Center</h1>
            </div>
            <div class="card" id="view-container">
                <p>Select a module from the sidebar to begin.</p>
            </div>
        </main>
    </div>
  `;

  const setActiveNav = (targetId: string) => {
    document
      .querySelectorAll(".nav-btn")
      .forEach((btn) => btn.classList.remove("active"));
    document.getElementById(targetId)?.classList.add("active");
  };

  document
    .getElementById("logoutBtn")
    ?.addEventListener("click", () => location.reload());

  document.getElementById("nav-map")?.addEventListener("click", () => {
    setActiveNav("nav-map");
    updateView(
      "Infrastructure Map",
      `<div id="map-target" style="width:100%; height:600px;"></div>`,
    );
    initMap("map-target");
  });

  document.getElementById("nav-people")?.addEventListener("click", () => {
    setActiveNav("nav-people");
    updateView(
      "People Management",
      `<p>Loading staff and customer records...</p>`,
    );
  });

  document.getElementById("nav-fleet")?.addEventListener("click", () => {
    setActiveNav("nav-fleet");
    updateView(
      "Fleet Overview",
      `<p>Active vehicles and maintenance logs.</p>`,
    );
  });
};

const updateView = (title: string, html: string) => {
  const titleEl = document.getElementById("view-title");
  const container = document.getElementById("view-container");

  if (titleEl) titleEl.innerText = title;
  if (container) container.innerHTML = html;
};

const appElement = document.querySelector("#app")!;

const initApp = () => {
  if (!authStore.getUser()) {
    renderLogin();
  } else {
    renderDashboard();
  }
};

window.addEventListener("DOMContentLoaded", initApp);
