import "./style.css";
import "./app.css";

import { Auth } from "../wailsjs/go/main/App";
import { initMap } from "./map";

const state = {
  isAuthenticated: false,
  username: "",
};

const renderLogin = () => {
  appElement.innerHTML = `
        <div class="auth-container">
            <div class="result" id="result">Please enter your credentials</div>
            <div class="input-box">
                <input class="input" id="username" type="text" placeholder="Username" />
                <input class="input" id="password" type="password" placeholder="Password" />
                <button class="btn" id="loginBtn">Login</button>
            </div>
            <div id="hint-text" class="hint"></div>
        </div>
    `;

  const loginBtn = document.getElementById("loginBtn");
  const userIn = document.getElementById("username") as HTMLInputElement;
  const passIn = document.getElementById("password") as HTMLInputElement;
  const resEl = document.getElementById("result");

  userIn.focus();

  loginBtn?.addEventListener("click", () => {
    const u = userIn.value;
    const p = passIn.value;

    if (!u || !p) {
      if (resEl) resEl.innerText = "Please fill in all fields.";
      return;
    }

    Auth(u, p).then((isValid) => {
      if (isValid) {
        state.isAuthenticated = true;
        state.username = u;
        initApp();
      } else {
        if (resEl) resEl.innerText = "Invalid credentials.";
      }
    });
  });
};

const renderDashboard = () => {
  appElement.innerHTML = `
        <div class="dashboard-layout">
            <nav class="sidebar">
                <h2>Logistics Pro</h2>
                <p>User: <strong>${state.username}</strong></p>
                <ul>
                    <li><button id="nav-map">🗺️ Map</button></li>
                    <li><button id="nav-people">👥 People</button></li>
                    <li><button id="nav-fleet">🚗 Fleet</button></li>
                </ul>
                <button class="btn-logout" id="logoutBtn">Logout</button>
            </nav>
            <main class="content-area" id="main-content">
                <h1>Command Center</h1>
                <div id="view-container">Select a module to begin.</div>
            </main>
        </div>
    `;

  document.getElementById("logoutBtn")?.addEventListener("click", () => {
    location.reload();
  });

  document.getElementById("nav-map")?.addEventListener("click", () => {
    const mainContent = document.getElementById("view-container");
    if (mainContent) {
      mainContent.innerHTML = `<h2>Infrastructure Map</h2><div id="map-target"></div>`;
      initMap("map-target"); // Kick off the canvas drawing
    }
  });
};

const appElement = document.querySelector("#app")!;

const initApp = () => {
  if (!state.isAuthenticated) {
    renderLogin();
  } else {
    renderDashboard();
  }
};

window.addEventListener("DOMContentLoaded", initApp);
