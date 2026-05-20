import {
  GetAllVehicles,
  CreateVehicle,
  UpdateVehicle,
  DeleteVehicle,
  GetVehicleTypes,
  CreateVehicleType,
  UpdateVehicleType,
  DeleteVehicleType,
} from "../wailsjs/go/main/App";
import { main, db } from "../wailsjs/go/models";
import { authStore } from "./auth";

let currentExpanded: number | null = null;

export const initFleet = async () => {
  const container = document.getElementById("view-container");
  if (!container) return;

  container.innerHTML = `
    <div class="users-toolbar">
      <div class="users-search">
        <input type="text" id="fleetSearch" placeholder="Search by plate or type..." />
        <select id="fleetStatusFilter">
          <option value="">All Statuses</option>
          <option value="Available">Available</option>
          <option value="On Route">On Route</option>
          <option value="Maintenance">Maintenance</option>
          <option value="Retired">Retired</option>
        </select>
      </div>
      <div>
        ${authStore.can("manage_vehicles") ? `<button class="btn-primary" id="add-vehicle-btn">+ Add Vehicle</button>` : ""}
        ${authStore.can("manage_vehicle_types") ? `<button class="btn-secondary" id="manage-types-btn">Manage Types</button>` : ""}
        <span class="users-count" id="fleetCount">Loading...</span>
      </div>
    </div>
    <div id="fleetTableWrap" class="users-table-wrap">
      <div class="loading-spinner">Loading fleet...</div>
    </div>
  `;

  try {
    const vehicles = await GetAllVehicles();
    renderFleetTable(vehicles);
  } catch (err) {
    container.innerHTML = `<p class="error-msg">Failed to load fleet: ${err}</p>`;
  }

  document.getElementById("add-vehicle-btn")?.addEventListener("click", () => {
    openVehicleModal(null);
  });
  document.getElementById("manage-types-btn")?.addEventListener("click", () => {
    openVehicleTypesManager();
  });
};

const statusBadge = (status: string) => {
  const cls = status.toLowerCase().replace(" ", "-");
  return `<span class="status-pill status-${cls}">${status}</span>`;
};

const renderFleetTable = (vehicles: main.VehicleDetail[]) => {
  const wrap = document.getElementById("fleetTableWrap");
  const count = document.getElementById("fleetCount");
  if (!wrap || !count) return;

  count.textContent = `${vehicles.length} vehicle${vehicles.length !== 1 ? "s" : ""}`;

  const vehicleAvatar = (v: main.VehicleDetail) => {
    const initial = v.license_plate.charAt(0).toUpperCase();
    const isElectric = v.type_name.toLowerCase().includes("electric");
    return `<span class="vehicle-avatar ${isElectric ? "vehicle-ev" : "vehicle-fuel"}">${initial}</span>`;
  };

  const canManage = authStore.can("manage_vehicles");

  const rows = vehicles
    .map(
      (v) => `
    <tr class="fleet-row ${currentExpanded === v.id ? "expanded" : ""}" data-vehicle-id="${v.id}">
      <td>
        <div class="user-cell">
          ${vehicleAvatar(v)}
          <div>
            <strong>${v.license_plate}</strong>
            <div class="user-sub">${v.type_name}</div>
          </div>
        </div>
      </td>
      <td>${v.type_name}</td>
      <td>${statusBadge(v.current_status)}</td>
      <td>${v.fuel_rate.toFixed(2)}</td>
      <td>${v.max_capacity.toFixed(0)} kg</td>
      <td>$${v.price_per_kg.toFixed(2)}</td>
    </tr>
    <tr class="fleet-detail-row ${currentExpanded === v.id ? "visible" : ""}" id="fleet-detail-${v.id}">
      <td colspan="6">
        <div class="user-detail-content" id="fleetDetailContent-${v.id}"></div>
      </td>
    </tr>
  `,
    )
    .join("");

  const searchHandler = () => {
    const q =
      (
        document.getElementById("fleetSearch") as HTMLInputElement
      )?.value.toLowerCase() || "";
    const statusFilter =
      (document.getElementById("fleetStatusFilter") as HTMLSelectElement)
        ?.value || "";
    document.querySelectorAll(".fleet-row").forEach((row) => {
      const el = row as HTMLElement;
      const vid = Number(el.dataset.vehicleId);
      const v = vehicles.find((x) => x.id === vid);
      if (!v) return;
      const textMatch =
        v.license_plate.toLowerCase().includes(q) ||
        v.type_name.toLowerCase().includes(q);
      const statusMatch = !statusFilter || v.current_status === statusFilter;
      const detailRow = document.getElementById(`fleet-detail-${vid}`);
      const show = textMatch && statusMatch;
      el.style.display = show ? "" : "none";
      if (detailRow) detailRow.style.display = show ? "" : "none";
    });
  };

  wrap.innerHTML = `
    <table class="users-table">
      <thead>
        <tr>
          <th>Vehicle</th>
          <th>Type</th>
          <th>Status</th>
          <th>Fuel Rate</th>
          <th>Max Capacity</th>
          <th>Price / kg</th>
        </tr>
      </thead>
      <tbody id="fleetTbody">${rows}</tbody>
    </table>
  `;

  const searchInput = document.getElementById("fleetSearch");
  const statusFilter = document.getElementById("fleetStatusFilter");
  searchInput?.addEventListener("input", searchHandler);
  statusFilter?.addEventListener("change", searchHandler);

  const tbody = document.getElementById("fleetTbody")!;
  tbody.addEventListener("click", async (e) => {
    const row = (e.target as HTMLElement).closest(
      ".fleet-row",
    ) as HTMLElement | null;
    if (!row) return;
    const vid = Number(row.dataset.vehicleId);
    const v = vehicles.find((x) => x.id === vid);
    if (!v) return;

    if (currentExpanded === vid) {
      collapseDetail(vid);
      currentExpanded = null;
      row.classList.remove("expanded");
      return;
    }

    if (currentExpanded !== null) {
      collapseDetail(currentExpanded);
      const prev = tbody.querySelector(
        `.fleet-row[data-vehicle-id="${currentExpanded}"]`,
      );
      prev?.classList.remove("expanded");
    }

    currentExpanded = vid;
    row.classList.add("expanded");
    const content = document.getElementById(`fleetDetailContent-${vid}`);
    if (content) {
      content.innerHTML = buildDetailHTML(v, canManage);
      wireFleetDetailButtons(v, canManage);
    }
    const detailRow = document.getElementById(`fleet-detail-${vid}`);
    if (detailRow) detailRow.classList.add("visible");
  });
};

const collapseDetail = (vid: number) => {
  const row = document.getElementById(`fleet-detail-${vid}`);
  if (row) row.classList.remove("visible");
};

const wireFleetDetailButtons = (v: main.VehicleDetail, canManage: boolean) => {
  if (!canManage) return;
  document
    .getElementById(`edit-vehicle-${v.id}`)
    ?.addEventListener("click", () => {
      openVehicleModal(v);
    });
  document
    .getElementById(`delete-vehicle-${v.id}`)
    ?.addEventListener("click", async () => {
      if (
        !confirm(`Delete vehicle "${v.license_plate}"? This cannot be undone.`)
      )
        return;
      try {
        await DeleteVehicle(v.id);
        initFleet();
      } catch (err: any) {
        alert(err.message || err);
      }
    });
};

const buildDetailHTML = (v: main.VehicleDetail, canManage: boolean) => {
  const actions = canManage
    ? `<div class="detail-actions">
        <button class="btn-primary" id="edit-vehicle-${v.id}">Edit</button>
        <button class="btn-danger" id="delete-vehicle-${v.id}">Delete</button>
      </div>`
    : "";

  return `
    <div class="detail-grid">
      <div class="detail-section">
        <h4>Vehicle Info</h4>
        <div class="profile-card">
          <div class="profile-avatar">${v.license_plate.charAt(0)}</div>
          <div class="profile-info">
            <div class="profile-name">${v.license_plate}</div>
            <span class="profile-type type-staff">${v.type_name}</span>
            <div class="profile-field"><span class="field-label">Status</span><span>${statusBadge(v.current_status)}</span></div>
            <div class="profile-field"><span class="field-label">Fuel Rate</span><span>${v.fuel_rate.toFixed(2)} / km</span></div>
            <div class="profile-field"><span class="field-label">Max Capacity</span><span>${v.max_capacity.toFixed(0)} kg</span></div>
            <div class="profile-field"><span class="field-label">Price / kg</span><span>$${v.price_per_kg.toFixed(4)}</span></div>
          </div>
        </div>
      </div>
      <div class="detail-section">
        <h4>Fuel & Cost</h4>
        <div class="metrics-grid">
          <div class="metric-tile" style="border-left: 3px solid #f39c12">
            <div class="metric-value">${v.fuel_rate.toFixed(2)}</div>
            <div class="metric-label">Fuel Rate / km</div>
          </div>
          <div class="metric-tile" style="border-left: 3px solid #9b59b6">
            <div class="metric-value">${v.max_capacity.toFixed(0)} kg</div>
            <div class="metric-label">Max Capacity</div>
          </div>
          <div class="metric-tile" style="border-left: 3px solid #2ecc71">
            <div class="metric-value">$${v.price_per_kg.toFixed(4)}</div>
            <div class="metric-label">Price / kg</div>
          </div>
        </div>
      </div>
      <div class="detail-section detail-full">
        <h4>Maintenance History</h4>
        <p class="muted">No maintenance records available.</p>
      </div>
      ${actions ? `<div class="detail-section detail-full">${actions}</div>` : ""}
    </div>
  `;
};

const openVehicleModal = async (vehicle: main.VehicleDetail | null) => {
  const overlay = document.getElementById("vehicle-modal-overlay");
  if (!overlay) {
    const div = document.createElement("div");
    div.innerHTML = `<div id="vehicle-modal-overlay" class="modal-overlay" style="display:flex;"><div class="modal-content" id="vehicle-modal-body"></div></div>`;
    document.body.appendChild(div.firstElementChild!);
  } else {
    overlay.style.display = "flex";
  }

  const body = document.getElementById("vehicle-modal-body")!;
  const isNew = !vehicle;

  let types: db.VehicleType[] = [];
  try {
    types = await GetVehicleTypes();
  } catch (_) { }

  const typeOptions = types
    .map(
      (t) =>
        `<option value="${t.id}" ${!isNew && t.type_name === vehicle!.type_name ? "selected" : ""}>${t.type_name}</option>`,
    )
    .join("");

  body.innerHTML = `
    <h3>${isNew ? "Add Vehicle" : `Edit: ${vehicle!.license_plate}`}</h3>
    <div class="modal-form">
      <label>
        License Plate
        <input id="modal-vehicle-plate" class="auth-input" type="text" value="${isNew ? "" : vehicle!.license_plate}" placeholder="e.g. EV-101" />
      </label>
      <label>
        Type
        <select id="modal-vehicle-type" class="auth-input">
          ${typeOptions || '<option value="">No types available</option>'}
        </select>
      </label>
      <label>
        Status
        <select id="modal-vehicle-status" class="auth-input">
          <option value="Available" ${!isNew && vehicle!.current_status === "Available" ? "selected" : ""}>Available</option>
          <option value="On Route" ${!isNew && vehicle!.current_status === "On Route" ? "selected" : ""}>On Route</option>
          <option value="Maintenance" ${!isNew && vehicle!.current_status === "Maintenance" ? "selected" : ""}>Maintenance</option>
          <option value="Retired" ${!isNew && vehicle!.current_status === "Retired" ? "selected" : ""}>Retired</option>
        </select>
      </label>
    </div>
    <div class="modal-actions">
      <button class="btn-primary" id="modal-vehicle-save-btn">${isNew ? "Create" : "Save"}</button>
      <button class="btn-cancel" id="modal-vehicle-cancel-btn">Cancel</button>
    </div>
    <p id="modal-vehicle-error" class="error-msg" style="display:none;"></p>
  `;

  let isSaving = false;
  const saveBtn = document.getElementById(
    "modal-vehicle-save-btn",
  ) as HTMLButtonElement;
  saveBtn?.addEventListener("click", async () => {
    if (isSaving) return;
    const plate = (
      document.getElementById("modal-vehicle-plate") as HTMLInputElement
    ).value.trim();
    const typeID = parseInt(
      (document.getElementById("modal-vehicle-type") as HTMLSelectElement)
        .value,
    );
    const status = (
      document.getElementById("modal-vehicle-status") as HTMLSelectElement
    ).value;
    const errEl = document.getElementById("modal-vehicle-error")!;

    if (!plate) {
      errEl.textContent = "License plate is required";
      errEl.style.display = "block";
      return;
    }
    if (isNaN(typeID)) {
      errEl.textContent = "Valid vehicle type is required";
      errEl.style.display = "block";
      return;
    }

    errEl.style.display = "none";
    isSaving = true;
    saveBtn.disabled = true;
    saveBtn.textContent = isNew ? "Creating..." : "Saving...";
    try {
      if (isNew) {
        await CreateVehicle(typeID, plate, status);
      } else {
        await UpdateVehicle(vehicle!.id, typeID, plate, status);
      }
      closeVehicleModal();
      initFleet();
    } catch (err: any) {
      errEl.textContent = err.message || err;
      errEl.style.display = "block";
    } finally {
      isSaving = false;
      saveBtn.disabled = false;
      saveBtn.textContent = isNew ? "Create" : "Save";
    }
  });

  document
    .getElementById("modal-vehicle-cancel-btn")
    ?.addEventListener("click", closeVehicleModal);

  const vOverlay = document.getElementById("vehicle-modal-overlay");
  if (vOverlay && !vOverlay.dataset.listenerReady) {
    vOverlay.addEventListener("click", (e) => {
      if (e.target === e.currentTarget) closeVehicleModal();
    });
    vOverlay.dataset.listenerReady = "true";
  }
};

const closeVehicleModal = () => {
  const overlay = document.getElementById("vehicle-modal-overlay");
  if (overlay) overlay.style.display = "none";
};

// Vehicle Types Manager

const openVehicleTypesManager = async () => {
  const overlay = document.getElementById("vtypes-modal-overlay");
  if (!overlay) {
    const div = document.createElement("div");
    div.innerHTML = `<div id="vtypes-modal-overlay" class="modal-overlay" style="display:flex;"><div class="modal-content modal-xl" id="vtypes-modal-body"></div></div>`;
    document.body.appendChild(div.firstElementChild!);
  } else {
    overlay.style.display = "flex";
  }

  const body = document.getElementById("vtypes-modal-body")!;
  await renderTypesList(body);
};

const renderTypesList = async (body: HTMLElement) => {
  let types: db.VehicleType[] = [];
  try {
    types = await GetVehicleTypes();
  } catch (_) { }

  const renderTable = (filtered: db.VehicleType[]) => {
    const tbody = document.getElementById("vtypes-tbody");
    if (!tbody) return;
    tbody.innerHTML =
      filtered.length === 0
        ? '<tr><td colspan="5" class="empty-row">No vehicle types found.</td></tr>'
        : filtered
          .map(
            (t) => `
          <tr style="color:white;">
            <td><strong>${escapeHtml(t.type_name)}</strong></td>
            <td>${t.fuel_rate.toFixed(2)} / km</td>
            <td>${t.max_capacity.toFixed(0)} kg</td>
            <td>$${t.price_per_kg.toFixed(4)}</td>
            <td class="actions-col">
              <button class="btn-primary btn-sm" id="vtype-edit-${t.id}">Edit</button>
              <button class="btn-danger btn-sm" id="vtype-delete-${t.id}">Delete</button>
            </td>
          </tr>
        `,
          )
          .join("");

    filtered.forEach((t) => {
      document
        .getElementById(`vtype-edit-${t.id}`)
        ?.addEventListener("click", () => {
          openVehicleTypeForm(t, body);
        });
      document
        .getElementById(`vtype-delete-${t.id}`)
        ?.addEventListener("click", async () => {
          if (!confirm(`Delete type "${t.type_name}"?`)) return;
          try {
            await DeleteVehicleType(t.id);
            const idx = types.findIndex((x) => x.id === t.id);
            if (idx >= 0) types.splice(idx, 1);
            renderTable(filtered.filter((x) => x.id !== t.id));
          } catch (err: any) {
            const errEl = document.getElementById("vtypes-error")!;
            errEl.textContent = err.message || err;
            errEl.style.display = "block";
          }
        });
    });
  };

  const filterTypes = () => {
    const q =
      (
        document.getElementById("vtypes-search") as HTMLInputElement
      )?.value.toLowerCase() || "";
    const filtered = q
      ? types.filter((t) => t.type_name.toLowerCase().includes(q))
      : types;
    renderTable(filtered);
  };

  body.innerHTML = `
    <div class="vtypes-header">
      <h3>Vehicle Types</h3>
      <button class="btn-primary" id="vtypes-add-btn">+ Add Type</button>
    </div>
    <input type="text" id="vtypes-search" class="auth-input" placeholder="Search by type name..." style="margin-bottom:0.75rem;" />
    <div class="vtypes-scroll">
      <table class="vtypes-table">
        <thead>
          <tr>
            <th class="vtypes-col">Name</th>
            <th class="vtypes-col">Fuel Rate</th>
            <th class="vtypes-col">Max Capacity</th>
            <th class="vtypes-col">Price / kg</th>
            <th class="actions-col">Actions</th>
          </tr>
        </thead>
        <tbody id="vtypes-tbody"></tbody>
      </table>
    </div>
    <div class="modal-actions">
      <button class="btn-cancel" id="vtypes-close-btn">Close</button>
    </div>
    <p id="vtypes-error" class="error-msg" style="display:none;"></p>
  `;

  filterTypes();

  document
    .getElementById("vtypes-search")
    ?.addEventListener("input", filterTypes);

  document.getElementById("vtypes-add-btn")?.addEventListener("click", () => {
    openVehicleTypeForm(null, body);
  });

  document.getElementById("vtypes-close-btn")?.addEventListener("click", () => {
    const overlay = document.getElementById("vtypes-modal-overlay");
    if (overlay) overlay.style.display = "none";
  });

  const vtOverlay = document.getElementById("vtypes-modal-overlay");
  if (vtOverlay && !vtOverlay.dataset.listenerReady) {
    vtOverlay.addEventListener("click", (e) => {
      if (e.target === e.currentTarget) {
        const overlay = document.getElementById("vtypes-modal-overlay");
        if (overlay) overlay.style.display = "none";
      }
    });
    vtOverlay.dataset.listenerReady = "true";
  }
};

const openVehicleTypeForm = (
  vt: db.VehicleType | null,
  parentBody: HTMLElement,
) => {
  const isNew = !vt;
  parentBody.innerHTML = `
    <h3>${isNew ? "Add Vehicle Type" : `Edit: ${vt!.type_name}`}</h3>
    <div class="modal-form">
      <label>
        Type Name
        <input id="vtype-name" class="auth-input" type="text" value="${isNew ? "" : escapeHtml(vt!.type_name)}" placeholder="e.g. Electric Van" />
      </label>
      <label>
        Fuel Rate (per km)
        <input id="vtype-fuel" class="auth-input" type="number" step="0.01" value="${isNew ? "" : vt!.fuel_rate}" placeholder="e.g. 1.50" />
      </label>
      <label>
        Max Capacity (kg)
        <input id="vtype-capacity" class="auth-input" type="number" step="0.1" value="${isNew ? "" : vt!.max_capacity}" placeholder="e.g. 5000" />
      </label>
      <label>
        Price per kg ($)
        <input id="vtype-price" class="auth-input" type="number" step="0.01" value="${isNew ? "" : vt!.price_per_kg}" placeholder="e.g. 10.00" />
      </label>
    </div>
    <div class="modal-actions">
      <button class="btn-primary" id="vtype-form-save-btn">${isNew ? "Create" : "Save"}</button>
      <button class="btn-cancel" id="vtype-form-back-btn">Back</button>
    </div>
    <p id="vtype-form-error" class="error-msg" style="display:none;"></p>
  `;

  let isSaving = false;
  const saveBtn = document.getElementById(
    "vtype-form-save-btn",
  ) as HTMLButtonElement;
  saveBtn?.addEventListener("click", async () => {
    if (isSaving) return;
    const name = (
      document.getElementById("vtype-name") as HTMLInputElement
    ).value.trim();
    const fuel = parseFloat(
      (document.getElementById("vtype-fuel") as HTMLInputElement).value,
    );
    const capacity = parseFloat(
      (document.getElementById("vtype-capacity") as HTMLInputElement).value,
    );
    const price = parseFloat(
      (document.getElementById("vtype-price") as HTMLInputElement).value,
    );
    const errEl = document.getElementById("vtype-form-error")!;

    if (!name) {
      errEl.textContent = "Type name is required";
      errEl.style.display = "block";
      return;
    }
    if (isNaN(fuel) || fuel <= 0) {
      errEl.textContent = "Valid fuel rate is required";
      errEl.style.display = "block";
      return;
    }
    if (isNaN(capacity) || capacity <= 0) {
      errEl.textContent = "Valid max capacity is required";
      errEl.style.display = "block";
      return;
    }
    if (isNaN(price) || price <= 0) {
      errEl.textContent = "Valid price per kg is required";
      errEl.style.display = "block";
      return;
    }

    errEl.style.display = "none";
    isSaving = true;
    saveBtn.disabled = true;
    saveBtn.textContent = isNew ? "Creating..." : "Saving...";
    try {
      if (isNew) {
        await CreateVehicleType(name, fuel, capacity, price);
      } else {
        await UpdateVehicleType(vt!.id, name, fuel, capacity, price);
      }
      await renderTypesList(parentBody);
    } catch (err: any) {
      errEl.textContent = err.message || err;
      errEl.style.display = "block";
    } finally {
      isSaving = false;
      saveBtn.disabled = false;
      saveBtn.textContent = isNew ? "Create" : "Save";
    }
  });

  document
    .getElementById("vtype-form-back-btn")
    ?.addEventListener("click", () => {
      renderTypesList(parentBody);
    });
};

function escapeHtml(s: string): string {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
