import { GetUsers, CreateUser, UpdateUser, DeleteUser, GetRoles } from "../wailsjs/go/main/App";
import { main, db } from "../wailsjs/go/models";
import { authStore } from "./auth";

let currentExpanded: number | null = null;

const STAFF_ROLES = [1, 2, 3, 4, 6, 7, 8, 9, 10]; // all except Customer

let _roles: db.Role[] = [];

export const renderUsersView = async () => {
  const container = document.getElementById("view-container");
  if (!container) return;

  try {
    const [users, roles] = await Promise.all([GetUsers(), GetRoles()]);
    _roles = roles;
    const activeRoles = roles.filter((r) => users.some((u) => u.role_name === r.role_name));

    container.innerHTML = `
      <div class="users-toolbar">
        <div class="users-search">
          <input type="text" id="usersSearch" placeholder="Search by username or name..." />
          <select id="usersRoleFilter">
            <option value="">All Roles</option>
            ${activeRoles.map((r) => `<option value="${r.role_name}">${r.role_name}</option>`).join("")}
          </select>
        </div>
        <div>
          ${authStore.can("manage_users") ? `<button class="btn-primary" id="add-user-btn">+ Add User</button>` : ""}
          <span class="users-count" id="usersCount">${users.length} user${users.length !== 1 ? "s" : ""}</span>
        </div>
      </div>
      <div id="usersTableWrap" class="users-table-wrap"></div>
    `;

    renderUserTable(users);
  } catch (err) {
    container.innerHTML = `<p class="error-msg">Failed to load users: ${err}</p>`;
    return;
  }

  document.getElementById("add-user-btn")?.addEventListener("click", () => {
    openUserModal(null);
  });
};

const renderUserTable = (users: main.UserDetail[]) => {
  const wrap = document.getElementById("usersTableWrap");
  const count = document.getElementById("usersCount");
  if (!wrap || !count) return;

  count.textContent = `${users.length} user${users.length !== 1 ? "s" : ""}`;

  const roleBadge = (role: string) => {
    const cls = role.toLowerCase();
    return `<span class="role-pill role-${cls}">${role}</span>`;
  };

  const personName = (u: main.UserDetail) => {
    if (!u.profile) return `<span class="muted">—</span>`;
    return `${u.profile.first_name} ${u.profile.last_name}`;
  };

  const metricsSummary = (u: main.UserDetail) => {
    const m = u.metrics;
    if (!m) return `<span class="muted">—</span>`;
    const parts: string[] = [];
    if (m.active_orders != null) parts.push(`${m.active_orders} active`);
    if (m.completed_orders != null)
      parts.push(`${m.completed_orders} completed`);
    if (m.failed_deliveries != null && m.failed_deliveries > 0)
      parts.push(`${m.failed_deliveries} failed`);
    if (m.total_orders != null) parts.push(`${m.total_orders} orders`);
    if (m.pending_orders != null) parts.push(`${m.pending_orders} pending`);
    if (parts.length === 0) return `<span class="muted">—</span>`;
    return parts.join(" · ");
  };

  const lastActive = (u: main.UserDetail) => {
    const at = u.metrics?.last_action_at;
    if (!at) return `<span class="muted">Never</span>`;
    const d = new Date(at);
    return `<span title="${d.toLocaleString()}">${timeAgo(d)}</span>`;
  };

  const canManage = authStore.can("manage_users");

  const rows = users
    .map(
      (u) => `
    <tr class="user-row ${currentExpanded === u.id ? "expanded" : ""}" data-user-id="${u.id}">
      <td>
        <div class="user-cell">
          <span class="user-avatar">${u.username.charAt(0).toUpperCase()}</span>
          <div>
            <strong>${u.username}</strong>
            ${u.profile ? `<div class="user-sub">${u.profile.first_name} ${u.profile.last_name}</div>` : ""}
          </div>
        </div>
      </td>
      <td>${roleBadge(u.role_name)}</td>
      <td>${personName(u)}</td>
      <td class="metrics-cell">${metricsSummary(u)}</td>
      <td class="last-active-cell">${lastActive(u)}</td>
    </tr>
    <tr class="user-detail-row ${currentExpanded === u.id ? "visible" : ""}" id="detail-${u.id}">
      <td colspan="5">
        <div class="user-detail-content" id="detailContent-${u.id}"></div>
      </td>
    </tr>
  `,
    )
    .join("");

  const searchHandler = () => {
    const q =
      (
        document.getElementById("usersSearch") as HTMLInputElement
      )?.value.toLowerCase() || "";
    const roleFilter =
      (document.getElementById("usersRoleFilter") as HTMLSelectElement)
        ?.value || "";
    document.querySelectorAll(".user-row").forEach((row) => {
      const el = row as HTMLElement;
      const uid = Number(el.dataset.userId);
      const u = users.find((x) => x.id === uid);
      if (!u) return;
      const nameMatch =
        u.username.toLowerCase().includes(q) ||
        (u.profile &&
          `${u.profile.first_name} ${u.profile.last_name}`
            .toLowerCase()
            .includes(q));
      const roleMatch = !roleFilter || u.role_name === roleFilter;
      const detailRow = document.getElementById(`detail-${uid}`);
      const show = nameMatch && roleMatch;
      el.style.display = show ? "" : "none";
      if (detailRow) detailRow.style.display = show ? "" : "none";
    });
  };

  wrap.innerHTML = `
    <table class="users-table">
      <thead>
        <tr>
          <th>User</th>
          <th>Role</th>
          <th>Person</th>
          <th>Activity</th>
          <th>Last Active</th>
        </tr>
      </thead>
      <tbody id="usersTbody">${rows}</tbody>
    </table>
  `;

  const searchInput = document.getElementById("usersSearch");
  const roleFilter = document.getElementById("usersRoleFilter");
  searchInput?.addEventListener("input", searchHandler);
  roleFilter?.addEventListener("change", searchHandler);

  const tbody = document.getElementById("usersTbody")!;
  tbody.addEventListener("click", async (e) => {
    const row = (e.target as HTMLElement).closest(
      ".user-row",
    ) as HTMLElement | null;
    if (!row) return;
    const uid = Number(row.dataset.userId);
    const u = users.find((x) => x.id === uid);
    if (!u) return;

    if (currentExpanded === uid) {
      collapseDetail(uid);
      currentExpanded = null;
      row.classList.remove("expanded");
      return;
    }

    if (currentExpanded !== null) {
      collapseDetail(currentExpanded);
      const prev = tbody.querySelector(
        `.user-row[data-user-id="${currentExpanded}"]`,
      );
      prev?.classList.remove("expanded");
    }

    currentExpanded = uid;
    row.classList.add("expanded");
    const content = document.getElementById(`detailContent-${uid}`);
    if (content) {
      try {
        content.innerHTML = buildDetailHTML(u, canManage);
        wireDetailButtons(u, canManage);
      } catch (err) {
        content.innerHTML = `<p class="error-msg">Failed to load details: ${err}</p>`;
        console.error("User detail error:", err);
      }
    }
    const detailRow = document.getElementById(`detail-${uid}`);
    if (detailRow) detailRow.classList.add("visible");
  });
};

const collapseDetail = (uid: number) => {
  const row = document.getElementById(`detail-${uid}`);
  if (row) row.classList.remove("visible");
};

const wireDetailButtons = (u: main.UserDetail, canManage: boolean) => {
  if (!canManage) return;
  document.getElementById(`edit-user-${u.id}`)?.addEventListener("click", () => {
    openUserModal(u);
  });
  document.getElementById(`delete-user-${u.id}`)?.addEventListener("click", async () => {
    if (!confirm(`Delete user "${u.username}"? This cannot be undone.`)) return;
    try {
      await DeleteUser(u.id);
      renderUsersView();
    } catch (err: any) {
      alert(err.message || err);
    }
  });
};

const buildDetailHTML = (u: main.UserDetail, canManage: boolean) => {
  const actions = canManage
    ? `<div class="detail-actions">
        <button class="btn-primary" id="edit-user-${u.id}">Edit</button>
        <button class="btn-danger" id="delete-user-${u.id}">Delete</button>
      </div>`
    : "";

  return `
    <div class="detail-grid">
      <div class="detail-section">
        <h4>Profile</h4>
        ${profileCard(u)}
      </div>
      <div class="detail-section">
        <h4>Metrics</h4>
        ${metricsCard(u)}
      </div>
      <div class="detail-section detail-full">
        <h4>Permissions</h4>
        <div class="perm-tags">
          ${u.permissions?.length > 0 ? u.permissions.map((p) => `<span class="perm-tag">${p}</span>`).join("") : '<span class="muted">No permissions assigned</span>'}
        </div>
      </div>
      <div class="detail-section detail-full">
        <h4>Recent Activity ${u.recent_actions?.length > 0 ? `<span class="badge">${u.recent_actions.length}</span>` : ""}</h4>
        ${auditTimeline(u.recent_actions)}
      </div>
      ${actions ? `<div class="detail-section detail-full">${actions}</div>` : ""}
    </div>
  `;
};

const ROLE_IDS: Record<string, number> = {};

const openUserModal = (user: main.UserDetail | null) => {
  const overlay = document.getElementById("user-modal-overlay");
  let modalHtml = `
    <div id="user-modal-overlay" class="modal-overlay" style="display:flex;">
      <div class="modal-content" id="user-modal-body"></div>
    </div>
  `;

  if (!overlay) {
    const div = document.createElement("div");
    div.innerHTML = modalHtml;
    document.body.appendChild(div.firstElementChild!);
  } else {
    overlay.style.display = "flex";
  }

  const body = document.getElementById("user-modal-body")!;
  _roles.forEach((r) => { ROLE_IDS[r.role_name] = r.id; });
  const isNew = !user;
  const isStaffRole = user ? STAFF_ROLES.includes(ROLE_IDS[user.role_name]) : true;

  const p = user?.profile;
  const profileFields = isStaffRole ? `
    <div id="profile-fields">
      <h4>Staff Profile</h4>
      <label>
        First Name
        <input id="modal-profile-first" class="auth-input" type="text" value="${p ? p.first_name : ""}" placeholder="First name" />
      </label>
      <label>
        Last Name
        <input id="modal-profile-last" class="auth-input" type="text" value="${p ? p.last_name : ""}" placeholder="Last name" />
      </label>
      <label>
        Position
        <input id="modal-profile-position" class="auth-input" type="text" value="${p?.position ?? ""}" placeholder="e.g. Driver, Manager" />
      </label>
      <label>
        Hire Date
        <input id="modal-profile-hiredate" class="auth-input" type="date" value="${p?.hire_date ?? ""}" />
      </label>
    </div>
  ` : `
    <div id="profile-fields">
      <h4>Customer Profile</h4>
      <label>
        First Name
        <input id="modal-profile-first" class="auth-input" type="text" value="${p ? p.first_name : ""}" placeholder="First name" />
      </label>
      <label>
        Last Name
        <input id="modal-profile-last" class="auth-input" type="text" value="${p ? p.last_name : ""}" placeholder="Last name" />
      </label>
      <label>
        Email
        <input id="modal-profile-email" class="auth-input" type="email" value="${p?.email ?? ""}" placeholder="email@example.com" />
      </label>
      <label>
        Phone
        <input id="modal-profile-phone" class="auth-input" type="text" value="${p?.phone ?? ""}" placeholder="+1-555-0000" />
      </label>
    </div>
  `;

  body.innerHTML = `
    <h3>${isNew ? "Add User" : `Edit: ${user!.username}`}</h3>
    <div class="modal-form">
      <label>
        Username
        <input id="modal-user-username" class="auth-input" type="text" value="${isNew ? "" : user!.username}" placeholder="Username" />
      </label>
      <label>
        Password ${isNew ? "" : "(leave blank to keep current)"}
        <input id="modal-user-password" class="auth-input" type="password" value="" placeholder="${isNew ? "Password" : "New password"}" />
      </label>
      <label>
        Role
        <select id="modal-user-role" class="auth-input">
          ${_roles.map((r) =>
            `<option value="${r.id}" ${!isNew && user!.role_name === r.role_name ? "selected" : ""}>${r.role_name}</option>`
          ).join("")}
        </select>
      </label>
      <hr />
      ${profileFields}
    </div>
    <div class="modal-actions">
      <button class="btn-primary" id="modal-user-save-btn">${isNew ? "Create" : "Save"}</button>
      <button class="btn-cancel" id="modal-user-cancel-btn">Cancel</button>
    </div>
    <p id="modal-user-error" class="error-msg" style="display:none;"></p>
  `;

  // Toggle profile fields when role changes
  document.getElementById("modal-user-role")?.addEventListener("change", (e) => {
    const roleVal = parseInt((e.target as HTMLSelectElement).value);
    const isStaff = STAFF_ROLES.includes(roleVal);
    const profileDiv = document.getElementById("profile-fields");
    if (profileDiv) {
      const heading = profileDiv.querySelector("h4");
      if (heading) heading.textContent = isStaff ? "Staff Profile" : "Customer Profile";
      const labelChildren = profileDiv.querySelectorAll("label");
      labelChildren.forEach((el) => el.remove());
      if (isStaff) {
        profileDiv.innerHTML = `
          <h4>Staff Profile</h4>
          <label>First Name<input id="modal-profile-first" class="auth-input" type="text" placeholder="First name" /></label>
          <label>Last Name<input id="modal-profile-last" class="auth-input" type="text" placeholder="Last name" /></label>
          <label>Position<input id="modal-profile-position" class="auth-input" type="text" placeholder="e.g. Driver, Manager" /></label>
          <label>Hire Date<input id="modal-profile-hiredate" class="auth-input" type="date" /></label>
        `;
      } else {
        profileDiv.innerHTML = `
          <h4>Customer Profile</h4>
          <label>First Name<input id="modal-profile-first" class="auth-input" type="text" placeholder="First name" /></label>
          <label>Last Name<input id="modal-profile-last" class="auth-input" type="text" placeholder="Last name" /></label>
          <label>Email<input id="modal-profile-email" class="auth-input" type="email" placeholder="email@example.com" /></label>
          <label>Phone<input id="modal-profile-phone" class="auth-input" type="text" placeholder="+1-555-0000" /></label>
        `;
      }
    }
  });

  let isSaving = false;
  const saveBtn = document.getElementById("modal-user-save-btn") as HTMLButtonElement;
  saveBtn?.addEventListener("click", async () => {
    if (isSaving) return;
    const username = (document.getElementById("modal-user-username") as HTMLInputElement).value.trim();
    const password = (document.getElementById("modal-user-password") as HTMLInputElement).value;
    const roleID = parseInt((document.getElementById("modal-user-role") as HTMLSelectElement).value);
    const errEl = document.getElementById("modal-user-error")!;

    if (!username) {
      errEl.textContent = "Username is required";
      errEl.style.display = "block";
      return;
    }
    if (isNew && !password) {
      errEl.textContent = "Password is required for new users";
      errEl.style.display = "block";
      return;
    }
    if (isNaN(roleID)) {
      errEl.textContent = "Valid role is required";
      errEl.style.display = "block";
      return;
    }

    const isStaff = STAFF_ROLES.includes(roleID);
    const first = (document.getElementById("modal-profile-first") as HTMLInputElement)?.value?.trim() ?? "";
    const last = (document.getElementById("modal-profile-last") as HTMLInputElement)?.value?.trim() ?? "";

    let profile: any = null;
    if (first || last) {
      if (isStaff) {
        profile = {
          first_name: first,
          last_name: last,
          position: (document.getElementById("modal-profile-position") as HTMLInputElement)?.value?.trim() ?? "",
          hire_date: (document.getElementById("modal-profile-hiredate") as HTMLInputElement)?.value ?? "",
        };
      } else {
        profile = {
          first_name: first,
          last_name: last,
          email: (document.getElementById("modal-profile-email") as HTMLInputElement)?.value?.trim() ?? "",
          phone: (document.getElementById("modal-profile-phone") as HTMLInputElement)?.value?.trim() ?? "",
        };
      }
    }

    errEl.style.display = "none";
    isSaving = true;
    saveBtn.disabled = true;
    saveBtn.textContent = isNew ? "Creating..." : "Saving...";
    try {
      if (isNew) {
        const payload: any = { username, password, role_id: roleID };
        if (profile) {
          if (isStaff) payload.staff_profile = profile;
          else payload.customer_profile = profile;
        }
        await CreateUser(payload);
      } else {
        const payload: any = { id: user!.id, username, password, role_id: roleID };
        if (profile) {
          if (isStaff) payload.staff_profile = profile;
          else payload.customer_profile = profile;
        }
        await UpdateUser(payload);
      }
      closeUserModal();
      renderUsersView();
    } catch (err: any) {
      errEl.textContent = err.message || err;
      errEl.style.display = "block";
    } finally {
      isSaving = false;
      saveBtn.disabled = false;
      saveBtn.textContent = isNew ? "Create" : "Save";
    }
  });

  document.getElementById("modal-user-cancel-btn")?.addEventListener("click", closeUserModal);

  document.getElementById("user-modal-overlay")?.addEventListener("click", (e) => {
    if (e.target === e.currentTarget) closeUserModal();
  });
};

const closeUserModal = () => {
  const overlay = document.getElementById("user-modal-overlay");
  if (overlay) overlay.style.display = "none";
};

const profileCard = (u: main.UserDetail) => {
  if (!u.profile) {
    return `<div class="profile-placeholder">
      <p class="muted">No linked profile</p>
      <p class="muted small">This user account has no staff or customer record attached.</p>
    </div>`;
  }
  const p = u.profile;
  const isStaff = p.type === "staff";
  return `
    <div class="profile-card">
      <div class="profile-avatar">${(p.first_name?.charAt(0) ?? "?")}${(p.last_name?.charAt(0) ?? "?")}</div>
      <div class="profile-info">
        <div class="profile-name">${p.first_name} ${p.last_name}</div>
        <span class="profile-type ${isStaff ? "type-staff" : "type-customer"}">${isStaff ? "Staff" : "Customer"}</span>
        ${isStaff && p.position ? `<div class="profile-field"><span class="field-label">Position</span><span>${p.position}</span></div>` : ""}
        ${isStaff && p.hire_date ? `<div class="profile-field"><span class="field-label">Hired</span><span>${p.hire_date}</span></div>` : ""}
        ${!isStaff && p.email ? `<div class="profile-field"><span class="field-label">Email</span><span>${p.email}</span></div>` : ""}
        ${!isStaff && p.phone ? `<div class="profile-field"><span class="field-label">Phone</span><span>${p.phone}</span></div>` : ""}
      </div>
    </div>
  `;
};

const metricsCard = (u: main.UserDetail) => {
  const m = u.metrics;
  if (!m) {
    return `<p class="muted">No metrics available</p>`;
  }

  type MetricTile = { label: string; value: string | number; color?: string };
  const tiles: MetricTile[] = [];

  if (m.active_orders != null)
    tiles.push({
      label: "Active Orders",
      value: m.active_orders,
      color: "#3498db",
    });
  if (m.completed_orders != null)
    tiles.push({
      label: "Completed",
      value: m.completed_orders,
      color: "#2ecc71",
    });
  if (m.failed_deliveries != null && m.failed_deliveries > 0)
    tiles.push({
      label: "Failed",
      value: m.failed_deliveries,
      color: "#e74c3c",
    });
  if (m.total_orders != null)
    tiles.push({
      label: "Total Orders",
      value: m.total_orders,
      color: "#f39c12",
    });
  if (m.pending_orders != null)
    tiles.push({ label: "Pending", value: m.pending_orders, color: "#f1c40f" });
  if (m.delivered_orders != null)
    tiles.push({
      label: "Delivered",
      value: m.delivered_orders,
      color: "#27ae60",
    });
  if (m.total_weight != null)
    tiles.push({
      label: "Total Weight",
      value: `${m.total_weight} kg`,
      color: "#9b59b6",
    });

  if (m.audit_log_count > 0) {
    tiles.push({
      label: "Audit Entries",
      value: m.audit_log_count,
      color: "#95a5a6",
    });
    if (m.last_action_at) {
      const d = new Date(m.last_action_at);
      tiles.push({
        label: "Last Active",
        value: d.toLocaleDateString(),
        color: "#7f8c8d",
      });
    }
  }

  if (tiles.length === 0) return `<p class="muted">No metrics available</p>`;

  return `
    <div class="metrics-grid">
      ${tiles
        .map(
          (t) => `
        <div class="metric-tile" ${t.color ? `style="border-left: 3px solid ${t.color}"` : ""}>
          <div class="metric-value">${t.value}</div>
          <div class="metric-label">${t.label}</div>
        </div>
      `,
        )
        .join("")}
    </div>
  `;
};

const auditTimeline = (entries: main.AuditEntry[]) => {
  if (!entries || entries.length === 0) {
    return `<p class="muted">No recorded activity</p>`;
  }
  return `
    <div class="audit-timeline">
      ${entries
        .map(
          (e) => `
        <div class="timeline-item">
          <div class="timeline-dot"></div>
          <div class="timeline-body">
            <div class="timeline-action">${escapeHtml(e.action)}</div>
            <div class="timeline-time">${new Date(e.timestamp).toLocaleString()}</div>
          </div>
        </div>
      `,
        )
        .join("")}
    </div>
  `;
};

function timeAgo(d: Date): string {
  const now = new Date();
  const sec = Math.floor((now.getTime() - d.getTime()) / 1000);
  if (sec < 60) return "just now";
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const days = Math.floor(hr / 24);
  if (days < 7) return `${days}d ago`;
  return d.toLocaleDateString();
}

function escapeHtml(s: string): string {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
