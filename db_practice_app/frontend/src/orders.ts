import { GetOrders, CreateOrder, UpdateOrder, DeleteOrder, UpdateOrderStatus, UpdateDeliveryStatus, DeleteDelivery, GetDrivers, GetAllVehicles, DispatchOrder, GetNetworkData, GetDeliveryRoutePath } from "../wailsjs/go/main/App";
import { main } from "../wailsjs/go/models";
import { authStore } from "./auth";
import { renderRouteMiniMap } from "./map";

let currentExpanded: number | null = null;

const STATUS_COLORS: Record<string, string> = {
  "Draft": "#6b7280",
  "Pending": "#f59e0b",
  "In Transit": "#3b82f6",
  "Delivered": "#10b981",
  "Failed": "#ef4444",
  "Cancelled": "#6b7280",
  "Returned": "#8b5cf6",
};

const DELIVERY_STATUS_COLORS: Record<string, string> = {
  "Pending": "#f59e0b",
  "In Transit": "#3b82f6",
  "Delivered": "#10b981",
  "Failed": "#ef4444",
};

export const renderOrdersView = async () => {
  const container = document.getElementById("view-container");
  if (!container) return;

  const user = authStore.getUser()!;
  const canManage = authStore.can("manage_orders");
  const isCustomer = user.role_name === "Customer";

  container.innerHTML = `
    <div class="users-toolbar">
      <div class="users-search">
        <input type="text" id="ordersSearch" placeholder="Search orders..." />
        <select id="ordersStatusFilter">
          <option value="">All Statuses</option>
          <option value="Draft">Draft</option>
          <option value="Pending">Pending</option>
          <option value="In Transit">In Transit</option>
          <option value="Delivered">Delivered</option>
          <option value="Failed">Failed</option>
          <option value="Cancelled">Cancelled</option>
          <option value="Returned">Returned</option>
        </select>
      </div>
      <div>
        ${canManage && !isCustomer ? `<button class="btn-primary" id="add-order-btn">+ New Order</button>` : ""}
        <span class="users-count" id="ordersCount">Loading...</span>
      </div>
    </div>
    <div id="ordersTableWrap" class="users-table-wrap">
      <div class="loading-spinner">Loading orders...</div>
    </div>
  `;

  try {
    const orders = await GetOrders();
    renderOrderTable(orders);
  } catch (err) {
    container.innerHTML = `<p class="error-msg">Failed to load orders: ${err}</p>`;
  }

  document.getElementById("add-order-btn")?.addEventListener("click", () => {
    openOrderModal(null);
  });
};

const statusPill = (status: string, map: Record<string, string>) => {
  const color = map[status] || "#6b7280";
  return `<span class="status-pill" style="background:${color}20;color:${color};border:1px solid ${color}40;">${status}</span>`;
};

const renderOrderTable = (orders: main.OrderDetail[]) => {
  const wrap = document.getElementById("ordersTableWrap");
  const count = document.getElementById("ordersCount");
  if (!wrap || !count) return;

  count.textContent = `${orders.length} order${orders.length !== 1 ? "s" : ""}`;

  const user = authStore.getUser()!;
  const canManage = authStore.can("manage_orders");
  const canUpdateStatus = authStore.can("update_order_status");
  const canViewCustomers = authStore.can("view_all_orders");
  const isCustomer = user.role_name === "Customer";

  const rows = orders.map((o) => `
    <tr class="user-row ${currentExpanded === o.id ? "expanded" : ""}" data-order-id="${o.id}">
      <td>#${o.id}</td>
      ${canViewCustomers && !isCustomer ? `<td>${escHtml(o.customer_name)}</td>` : ""}
      <td>${escHtml(o.pickup_node_label || `Node ${o.pickup_node_id}`)}</td>
      <td>${escHtml(o.dropoff_node_label || `Node ${o.dropoff_node_id}`)}</td>
      <td>${o.order_date ? new Date(o.order_date).toLocaleDateString() : "—"}</td>
      <td>${o.total_weight} kg</td>
      <td>${statusPill(o.status, STATUS_COLORS)}</td>
    </tr>
    <tr class="user-detail-row ${currentExpanded === o.id ? "visible" : ""}" id="detail-${o.id}">
      <td colspan="${canViewCustomers && !isCustomer ? 7 : 6}">
        <div class="user-detail-content" id="detailContent-${o.id}"></div>
      </td>
    </tr>
  `).join("");

  const searchHandler = () => {
    const q = (document.getElementById("ordersSearch") as HTMLInputElement)?.value.toLowerCase() || "";
    const statusFilter = (document.getElementById("ordersStatusFilter") as HTMLSelectElement)?.value || "";
    document.querySelectorAll(".user-row[data-order-id]").forEach((row) => {
      const el = row as HTMLElement;
      const oid = Number(el.dataset.orderId);
      const o = orders.find((x) => x.id === oid);
      if (!o) return;
      const match = `${o.id} ${o.customer_name} ${o.pickup_node_label} ${o.dropoff_node_label} ${o.status}`.toLowerCase().includes(q);
      const statusMatch = !statusFilter || o.status === statusFilter;
      const detailRow = document.getElementById(`detail-${oid}`);
      const show = match && statusMatch;
      el.style.display = show ? "" : "none";
      if (detailRow) detailRow.style.display = show ? "" : "none";
    });
  };

  const headers = ["ID", ...(canViewCustomers && !isCustomer ? ["Customer"] : []), "Pickup", "Dropoff", "Date", "Weight", "Status"];

  wrap.innerHTML = `
    <table class="users-table">
      <thead>
        <tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr>
      </thead>
      <tbody id="ordersTbody">${rows}</tbody>
    </table>
  `;

  document.getElementById("ordersSearch")?.addEventListener("input", searchHandler);
  document.getElementById("ordersStatusFilter")?.addEventListener("change", searchHandler);

  const tbody = document.getElementById("ordersTbody")!;
  tbody.addEventListener("click", async (e) => {
    const row = (e.target as HTMLElement).closest(".user-row[data-order-id]") as HTMLElement | null;
    if (!row) return;
    const oid = Number(row.dataset.orderId);
    const o = orders.find((x) => x.id === oid);
    if (!o) return;

    if (currentExpanded === oid) {
      collapseDetail(oid);
      currentExpanded = null;
      row.classList.remove("expanded");
      return;
    }

    if (currentExpanded !== null) {
      collapseDetail(currentExpanded);
      tbody.querySelector(`.user-row[data-order-id="${currentExpanded}"]`)?.classList.remove("expanded");
    }

    currentExpanded = oid;
    row.classList.add("expanded");
    const content = document.getElementById(`detailContent-${oid}`);
    if (content) {
      content.innerHTML = buildDetailHTML(o, canManage, canUpdateStatus, isCustomer);
      wireDetailButtons(o, canManage, isCustomer);
    }
    const detailRow = document.getElementById(`detail-${oid}`);
    if (detailRow) detailRow.classList.add("visible");
  });
};

const collapseDetail = (oid: number) => {
  const row = document.getElementById(`detail-${oid}`);
  if (row) row.classList.remove("visible");
};

const buildDetailHTML = (o: main.OrderDetail, canManage: boolean, canUpdateStatus: boolean, isCustomer: boolean) => {
  const canManageDeliveries = authStore.can("manage_deliveries");

  const actions = canManage && !isCustomer
    ? `<div class="detail-actions">
        <button class="btn-primary" id="edit-order-${o.id}">Edit</button>
        <button class="btn-danger" id="delete-order-${o.id}">Delete</button>
      </div>`
    : "";

  const statusActions = canUpdateStatus && !isCustomer ? `
    <div class="status-update">
      <select id="order-status-select-${o.id}" class="auth-input" style="width:auto;display:inline-block;">
        <option value="Draft" ${o.status === "Draft" ? "selected" : ""}>Draft</option>
        <option value="Pending" ${o.status === "Pending" ? "selected" : ""}>Pending</option>
        <option value="In Transit" ${o.status === "In Transit" ? "selected" : ""}>In Transit</option>
        <option value="Delivered" ${o.status === "Delivered" ? "selected" : ""}>Delivered</option>
        <option value="Failed" ${o.status === "Failed" ? "selected" : ""}>Failed</option>
        <option value="Cancelled" ${o.status === "Cancelled" ? "selected" : ""}>Cancelled</option>
        <option value="Returned" ${o.status === "Returned" ? "selected" : ""}>Returned</option>
      </select>
      <button class="btn-sm btn-secondary" id="apply-order-status-${o.id}">Update</button>
    </div>` : "";

  const routeSection = o.deliveries && o.deliveries.length > 0 ? `
    <div class="detail-section detail-full route-card">
      <h4>🚚 Route Assignment</h4>
      ${o.deliveries.map((d) => `
        <div class="route-delivery" data-delivery-id="${d.id}">
          <div class="route-meta">
            <span class="route-driver">🚚 ${d.driver_name || "—"} (${d.vehicle_plate || "—"})</span>
            <span class="route-status">${statusPill(d.status, DELIVERY_STATUS_COLORS)}</span>
          </div>
          <div class="route-details" id="route-details-${d.id}">
            <span class="loading-spinner" style="display:inline;padding:0;font-size:0.8rem;">Loading route...</span>
          </div>
          <canvas id="route-map-${d.id}" class="route-mini-map" width="500" height="150"></canvas>
          <div class="route-actions">
            ${d.status !== "Delivered" && d.status !== "Failed" ? `
              <select class="delivery-status-select" data-delivery-id="${d.id}">
                <option value="">Change status...</option>
                <option value="In Transit">In Transit</option>
                <option value="Delivered">Delivered</option>
                <option value="Failed">Failed</option>
              </select>
            ` : ""}
            ${canManageDeliveries ? `<button class="btn-sm btn-danger delivery-delete-btn" data-delivery-id="${d.id}">Delete</button>` : ""}
          </div>
        </div>
      `).join("")}
    </div>` : "";

  const dispatchSection = !o.deliveries?.length && canManageDeliveries
    ? `<div class="detail-section"><button class="btn-primary" id="dispatch-order-${o.id}">🚀 Dispatch Order</button></div>`
    : "";

  return `
    <div class="detail-grid">
      <div class="detail-section">
        <h4>Order Info</h4>
        <div class="info-grid">
          <div><span class="field-label">Customer</span><span>${escHtml(o.customer_name)}</span></div>
          <div><span class="field-label">Pickup</span><span>${escHtml(o.pickup_node_label || `Node ${o.pickup_node_id}`)}</span></div>
          <div><span class="field-label">Dropoff</span><span>${escHtml(o.dropoff_node_label || `Node ${o.dropoff_node_id}`)}</span></div>
          <div><span class="field-label">Date</span><span>${o.order_date || "—"}</span></div>
          <div><span class="field-label">Weight</span><span>${o.total_weight} kg</span></div>
          <div><span class="field-label">Status</span><span>${statusPill(o.status, STATUS_COLORS)}</span></div>
        </div>
      </div>
      ${statusActions ? `<div class="detail-section">${statusActions}</div>` : ""}
      ${routeSection}
      ${dispatchSection}
      ${actions ? `<div class="detail-section detail-full">${actions}</div>` : ""}
    </div>
  `;
};

const wireDetailButtons = (o: main.OrderDetail, canManage: boolean, isCustomer: boolean) => {
  if (canManage && !isCustomer) {
    document.getElementById(`edit-order-${o.id}`)?.addEventListener("click", () => {
      openOrderModal(o);
    });
    document.getElementById(`delete-order-${o.id}`)?.addEventListener("click", async () => {
      if (!confirm(`Delete order #${o.id}? This cannot be undone.`)) return;
      try {
        await DeleteOrder(o.id);
        renderOrdersView();
      } catch (err: any) {
        alert(err.message || err);
      }
    });
  }

  document.getElementById(`apply-order-status-${o.id}`)?.addEventListener("click", async () => {
    const select = document.getElementById(`order-status-select-${o.id}`) as HTMLSelectElement;
    if (!select) return;
    const status = select.value;
    if (!status || status === o.status) return;
    if (!confirm(`Change order #${o.id} status to "${status}"?`)) return;
    try {
      await UpdateOrderStatus(o.id, status);
      renderOrdersView();
    } catch (err: any) {
      alert(err.message || err);
    }
  });

  document.querySelectorAll(`#detailContent-${o.id} .delivery-status-select`).forEach((sel) => {
    sel.addEventListener("change", async (e) => {
      const target = e.target as HTMLSelectElement;
      const did = Number(target.dataset.deliveryId);
      const status = target.value;
      if (!status) return;
      if (!confirm(`Update delivery #${did} to "${status}"?`)) return;
      try {
        await UpdateDeliveryStatus(did, status);
        renderOrdersView();
      } catch (err: any) {
        alert(err.message || err);
      }
    });
  });

  document.querySelectorAll(`#detailContent-${o.id} .delivery-delete-btn`).forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      const did = Number((e.currentTarget as HTMLElement).dataset.deliveryId);
      if (!confirm(`Delete delivery #${did}? This cannot be undone.`)) return;
      try {
        await DeleteDelivery(did);
        renderOrdersView();
      } catch (err: any) {
        alert(err.message || err);
      }
    });
  });

  document.getElementById(`dispatch-order-${o.id}`)?.addEventListener("click", () => {
    openDispatchModal(o.id);
  });

  loadRouteDetails(o);
};

const loadRouteDetails = async (o: main.OrderDetail) => {
  if (!o.deliveries || o.deliveries.length === 0) return;

  try {
    const [networkData, ...routes] = await Promise.all([
      GetNetworkData(),
      ...o.deliveries.map((d) => GetDeliveryRoutePath(d.id)),
    ]);

    const nodeLabel = new Map<number, string>();
    for (const n of networkData.nodes) {
      nodeLabel.set(n.id, n.label || `Node ${n.id}`);
    }

    for (let i = 0; i < o.deliveries.length; i++) {
      const route = routes[i];
      const d = o.deliveries[i];
      const detailsEl = document.getElementById(`route-details-${d.id}`);
      const canvas = document.getElementById(`route-map-${d.id}`) as HTMLCanvasElement;
      if (!detailsEl) continue;

      let pathStr = nodeLabel.get(route.pickup_node_id) || `Node ${route.pickup_node_id}`;
      let prevNodeId = route.pickup_node_id;
      for (const seg of route.segments) {
        const nextNodeId = seg.node_a_id === prevNodeId ? seg.node_b_id : seg.node_a_id;
        pathStr += ` → ${nodeLabel.get(nextNodeId) || `Node ${nextNodeId}`}`;
        prevNodeId = nextNodeId;
      }

      detailsEl.innerHTML = `
        <div class="route-path">${pathStr}</div>
        <div class="route-stats">
          📏 ${route.total_distance.toFixed(1)} km
          <span class="sep">·</span>
          ⏱ ${route.total_time.toFixed(2)} hrs
        </div>
      `;

      if (canvas) {
        const dpr = window.devicePixelRatio || 1;
        const rect = canvas.getBoundingClientRect();
        canvas.width = rect.width * dpr;
        canvas.height = rect.height * dpr;

        renderRouteMiniMap(
          canvas,
          networkData.nodes,
          networkData.edges,
          route.segments.map((s) => s.edge_id),
          route.pickup_node_id,
          route.dropoff_node_id,
          dpr,
        );
      }
    }
  } catch (err) {
    for (const d of o.deliveries) {
      const el = document.getElementById(`route-details-${d.id}`);
      if (el) el.innerHTML = `<span class="error-msg">Route data: ${err}</span>`;
    }
  }
};

// ── Node lookup for modal ──

let _cachedNodes: { id: number; label: string }[] = [];

const loadNodes = async (): Promise<{ id: number; label: string }[]> => {
  if (_cachedNodes.length > 0) return _cachedNodes;
  try {
    const { GetNetworkData } = await import("../wailsjs/go/main/App");
    const data = await GetNetworkData();
    _cachedNodes = data.nodes.map((n: any) => ({ id: n.id, label: n.label || `Node ${n.id}` }));
    return _cachedNodes;
  } catch {
    return _cachedNodes;
  }
};

const openOrderModal = async (order: main.OrderDetail | null) => {
  const nodes = await loadNodes();
  const overlay = document.getElementById("order-modal-overlay");

  if (!overlay) {
    const div = document.createElement("div");
    div.innerHTML = `<div id="order-modal-overlay" class="modal-overlay" style="display:flex;"><div class="modal-content" id="order-modal-body"></div></div>`;
    document.body.appendChild(div.firstElementChild!);
  } else {
    overlay.style.display = "flex";
  }

  const body = document.getElementById("order-modal-body")!;
  const isNew = !order;

  const nodeOptions = (selectedId: number) =>
    nodes.map((n) => `<option value="${n.id}" ${n.id === selectedId ? "selected" : ""}>${escHtml(n.label)}</option>`).join("");

  const canSelectCustomer = authStore.can("view_all_orders");

  body.innerHTML = `
    <h3>${isNew ? "New Order" : `Edit Order #${order!.id}`}</h3>
    <div class="modal-form">
      ${canSelectCustomer ? `
      <label>
        Customer
        <select id="modal-order-customer" class="auth-input">
          <option value="">Select customer...</option>
        </select>
      </label>
      ` : ""}
      <label>
        Pickup Node
        <select id="modal-order-pickup" class="auth-input">
          <option value="">Select pickup...</option>
          ${nodeOptions(order ? order.pickup_node_id : 0)}
        </select>
      </label>
      <label>
        Dropoff Node
        <select id="modal-order-dropoff" class="auth-input">
          <option value="">Select dropoff...</option>
          ${nodeOptions(order ? order.dropoff_node_id : 0)}
        </select>
      </label>
      <label>
        Total Weight (kg)
        <input id="modal-order-weight" class="auth-input" type="number" step="0.1" min="0" value="${order ? order.total_weight : ""}" />
      </label>
    </div>
    <div class="modal-actions">
      <button class="btn-primary" id="modal-order-save-btn">${isNew ? "Create" : "Save"}</button>
      <button class="btn-cancel" id="modal-order-cancel-btn">Cancel</button>
    </div>
    <p id="modal-order-error" class="error-msg" style="display:none;"></p>
  `;

  // Load customer dropdown if admin/manager
  if (canSelectCustomer) {
    try {
      const { GetUsers } = await import("../wailsjs/go/main/App");
      const users = await GetUsers();
      const customers = users.filter((u: any) => u.role_name === "Customer" && u.profile);
      const sel = document.getElementById("modal-order-customer") as HTMLSelectElement;
      if (sel) {
        sel.innerHTML = `<option value="">Select customer...</option>${customers.map((c: any) => `<option value="${c.id}">${escHtml(c.profile.first_name)} ${escHtml(c.profile.last_name)}</option>`).join("")}`;
      }
    } catch { /* ignore */ }
  }

  let isSaving = false;
  const saveBtn = document.getElementById("modal-order-save-btn") as HTMLButtonElement;
  saveBtn?.addEventListener("click", async () => {
    if (isSaving) return;
    const errEl = document.getElementById("modal-order-error")!;

    const user = authStore.getUser()!;
    const customerId = canSelectCustomer
      ? parseInt((document.getElementById("modal-order-customer") as HTMLSelectElement)?.value || "0")
      : (user as any).customer_id || 0;
    const pickupId = parseInt((document.getElementById("modal-order-pickup") as HTMLSelectElement)?.value || "0");
    const dropoffId = parseInt((document.getElementById("modal-order-dropoff") as HTMLSelectElement)?.value || "0");
    const weight = parseFloat((document.getElementById("modal-order-weight") as HTMLInputElement)?.value || "0");

    if (!pickupId || !dropoffId) {
      errEl.textContent = "Pickup and dropoff nodes are required";
      errEl.style.display = "block";
      return;
    }
    if (pickupId === dropoffId) {
      errEl.textContent = "Pickup and dropoff must be different nodes";
      errEl.style.display = "block";
      return;
    }
    if (!customerId) {
      errEl.textContent = "Customer is required";
      errEl.style.display = "block";
      return;
    }
    if (weight <= 0) {
      errEl.textContent = "Weight must be greater than 0";
      errEl.style.display = "block";
      return;
    }

    errEl.style.display = "none";
    isSaving = true;
    saveBtn.disabled = true;
    saveBtn.textContent = isNew ? "Creating..." : "Saving...";
    try {
      if (isNew) {
        await CreateOrder({ customer_id: customerId, pickup_node_id: pickupId, dropoff_node_id: dropoffId, total_weight: weight });
      } else {
        await UpdateOrder({ id: order!.id, pickup_node_id: pickupId, dropoff_node_id: dropoffId, total_weight: weight });
      }
      closeOrderModal();
      renderOrdersView();
    } catch (err: any) {
      errEl.textContent = err.message || err;
      errEl.style.display = "block";
    } finally {
      isSaving = false;
      saveBtn.disabled = false;
      saveBtn.textContent = isNew ? "Create" : "Save";
    }
  });

  document.getElementById("modal-order-cancel-btn")?.addEventListener("click", closeOrderModal);
  const orderOverlay = document.getElementById("order-modal-overlay");
  if (orderOverlay && !orderOverlay.dataset.listenerReady) {
    orderOverlay.addEventListener("click", (e) => {
      if (e.target === e.currentTarget) closeOrderModal();
    });
    orderOverlay.dataset.listenerReady = "true";
  }
};

const closeOrderModal = () => {
  const overlay = document.getElementById("order-modal-overlay");
  if (overlay) overlay.style.display = "none";
};

const openDispatchModal = async (orderID: number) => {
  const overlay = document.getElementById("dispatch-modal-overlay");

  if (!overlay) {
    const div = document.createElement("div");
    div.innerHTML = `<div id="dispatch-modal-overlay" class="modal-overlay" style="display:flex;"><div class="modal-content" id="dispatch-modal-body"></div></div>`;
    document.body.appendChild(div.firstElementChild!);
  } else {
    overlay.style.display = "flex";
  }

  const body = document.getElementById("dispatch-modal-body")!;
  body.innerHTML = `<div class="loading-spinner">Loading drivers and vehicles...</div>`;

  try {
    const [drivers, vehicles] = await Promise.all([
      GetDrivers(),
      GetAllVehicles(),
    ]);
    const availVehicles = vehicles.filter((v: any) => v.current_status === "Available");

    body.innerHTML = `
      <h3>Dispatch Order #${orderID}</h3>
      <div class="modal-form">
        <label>
          Driver
          <select id="dispatch-driver" class="auth-input">
            <option value="">Select driver...</option>
            ${drivers.map((d: any) => `<option value="${d.id}">${escHtml(d.first_name)} ${escHtml(d.last_name)}</option>`).join("")}
          </select>
        </label>
        <label>
          Vehicle
          <select id="dispatch-vehicle" class="auth-input">
            <option value="">Select vehicle...</option>
            ${availVehicles.map((v: any) => `<option value="${v.id}">${escHtml(v.license_plate)} (${escHtml(v.type_name)})</option>`).join("")}
          </select>
        </label>
      </div>
      <div class="modal-actions">
        <button class="btn-primary" id="dispatch-save-btn">Dispatch</button>
        <button class="btn-cancel" id="dispatch-cancel-btn">Cancel</button>
      </div>
      <p id="dispatch-error" class="error-msg" style="display:none;"></p>
    `;

    let isSaving = false;
    const saveBtn = document.getElementById("dispatch-save-btn") as HTMLButtonElement;
    saveBtn?.addEventListener("click", async () => {
      if (isSaving) return;
      const driverID = parseInt((document.getElementById("dispatch-driver") as HTMLSelectElement)?.value || "0");
      const vehicleID = parseInt((document.getElementById("dispatch-vehicle") as HTMLSelectElement)?.value || "0");
      const errEl = document.getElementById("dispatch-error")!;

      if (!driverID) {
        errEl.textContent = "Select a driver";
        errEl.style.display = "block";
        return;
      }
      if (!vehicleID) {
        errEl.textContent = "Select a vehicle";
        errEl.style.display = "block";
        return;
      }

      errEl.style.display = "none";
      isSaving = true;
      saveBtn.disabled = true;
      saveBtn.textContent = "Dispatching...";
      try {
        await DispatchOrder(orderID, driverID, vehicleID);
        closeDispatchModal();
        renderOrdersView();
      } catch (err: any) {
        errEl.textContent = err.message || err;
        errEl.style.display = "block";
      } finally {
        isSaving = false;
        saveBtn.disabled = false;
        saveBtn.textContent = "Dispatch";
      }
    });

    document.getElementById("dispatch-cancel-btn")?.addEventListener("click", closeDispatchModal);
    const dispatchOverlay = document.getElementById("dispatch-modal-overlay");
    if (dispatchOverlay && !dispatchOverlay.dataset.listenerReady) {
      dispatchOverlay.addEventListener("click", (e) => {
        if (e.target === e.currentTarget) closeDispatchModal();
      });
      dispatchOverlay.dataset.listenerReady = "true";
    }
  } catch (err: any) {
    body.innerHTML = `<p class="error-msg">Failed to load data: ${err}</p>`;
  }
};

const closeDispatchModal = () => {
  const overlay = document.getElementById("dispatch-modal-overlay");
  if (overlay) overlay.style.display = "none";
};

function escHtml(s: string): string {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
