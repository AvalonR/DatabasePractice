import {
  GetNetworkData,
  GetNodeDetails,
  CreateNode,
  UpdateNode,
  DeleteNode,
  CreateEdge,
  UpdateEdge,
  DeleteEdge,
  GetOrderRouteEdgeIds,
} from "../wailsjs/go/main/App";
import { db } from "../wailsjs/go/models";
import { main } from "../wailsjs/go/models";
import { authStore } from "./auth";
import { renderOrdersView } from "./orders";

export const renderRouteMiniMap = (
  canvas: HTMLCanvasElement,
  nodes: db.Node[],
  edges: db.Edge[],
  routeEdgeIDs: number[],
  pickupNodeID: number,
  dropoffNodeID: number,
  dpr: number = 1,
) => {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const w = canvas.width / dpr;
  const h = canvas.height / dpr;

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#1a1a2e";
  ctx.fillRect(0, 0, w, h);

  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  for (const n of nodes) {
    if (n.x_coord < minX) minX = n.x_coord;
    if (n.y_coord < minY) minY = n.y_coord;
    if (n.x_coord > maxX) maxX = n.x_coord;
    if (n.y_coord > maxY) maxY = n.y_coord;
  }

  const pad = 30;
  const rx = maxX - minX || 1;
  const ry = maxY - minY || 1;
  const sc = Math.min((w - pad * 2) / rx, (h - pad * 2) / ry);
  const ox = (w - rx * sc) / 2 - minX * sc;
  const oy = (h - ry * sc) / 2 - minY * sc;

  const tx = (x: number) => x * sc + ox;
  const ty = (y: number) => y * sc + oy;

  const routeSet = new Set(routeEdgeIDs);

  const routeNodeIDs = new Set<number>();
  routeNodeIDs.add(pickupNodeID);
  routeNodeIDs.add(dropoffNodeID);
  for (const edge of edges) {
    if (routeSet.has(edge.id)) {
      routeNodeIDs.add(edge.node_a_id);
      routeNodeIDs.add(edge.node_b_id);
    }
  }

  for (const edge of edges) {
    const sn = nodes.find((n) => n.id === edge.node_a_id);
    const en = nodes.find((n) => n.id === edge.node_b_id);
    if (!sn || !en) continue;
    const isRoute = routeSet.has(edge.id);
    ctx.strokeStyle = isRoute ? "#00ff88" : "#333";
    ctx.lineWidth = isRoute ? 2.5 : 0.5;
    ctx.beginPath();
    ctx.moveTo(tx(sn.x_coord), ty(sn.y_coord));
    ctx.lineTo(tx(en.x_coord), ty(en.y_coord));
    ctx.stroke();

    if (isRoute) {
      const mx = (tx(sn.x_coord) + tx(en.x_coord)) / 2;
      const my = (ty(sn.y_coord) + ty(en.y_coord)) / 2;
      ctx.fillStyle = "#88ffaa";
      ctx.font = "9px monospace";
      ctx.fillText(`${edge.distance_units}km`, mx - 10, my - 5);
    }
  }

  for (const node of nodes) {
    const x = tx(node.x_coord);
    const y = ty(node.y_coord);
    const isRouteNode = routeNodeIDs.has(node.id);

    if (node.id === pickupNodeID) {
      ctx.fillStyle = "#2ecc71";
    } else if (node.id === dropoffNodeID) {
      ctx.fillStyle = "#e74c3c";
    } else if (isRouteNode) {
      ctx.fillStyle = "#3498db";
    } else {
      ctx.fillStyle = "#555";
    }

    const rad = isRouteNode ? 4 : 2;
    ctx.beginPath();
    ctx.arc(x, y, rad, 0, Math.PI * 2);
    ctx.fill();

    if (isRouteNode) {
      ctx.fillStyle = "#aaa";
      ctx.font = "9px monospace";
      ctx.fillText(node.label, x + 6, y - 4);
    }
  }
};

export const initMap = async (containerId: string) => {
  const container = document.getElementById(containerId);
  if (!container) return;

  container.innerHTML = `
    <div style="position: relative;">
      <canvas id="mapCanvas" width="800" height="600" style="border:1px solid #444; background: #222; cursor: crosshair;"></canvas>
      <div id="map-tooltip" style="display: none; position: absolute; background: #333; color: white; padding: 12px; border-radius: 8px; border: 1px solid #555; pointer-events: auto; z-index: 100; box-shadow: 0 4px 15px rgba(0,0,0,0.5); min-width: 200px; overflow: hidden;"></div>
      <div style="position: absolute; top: 10px; right: 10px; display: flex; flex-direction: column; gap: 4px; z-index: 50;">
        <button id="zoom-in-btn" style="width: 32px; height: 32px; background: #444; color: white; border: 1px solid #666; border-radius: 4px; cursor: pointer; font-size: 18px; line-height: 1;">+</button>
        <button id="zoom-out-btn" style="width: 32px; height: 32px; background: #444; color: white; border: 1px solid #666; border-radius: 4px; cursor: pointer; font-size: 18px; line-height: 1;">−</button>
        <button id="zoom-reset-btn" style="width: 32px; height: 32px; background: #444; color: white; border: 1px solid #666; border-radius: 4px; cursor: pointer; font-size: 12px; line-height: 1;">⟲</button>
      </div>
    </div>`;

  const canvas = document.getElementById("mapCanvas") as HTMLCanvasElement;
  const tooltip = document.getElementById("map-tooltip") as HTMLDivElement;

  // Make tooltip draggable by its handle
  if (!tooltip.dataset.dragReady) {
    tooltip.addEventListener("mousedown", (e) => {
      const handle = (e.target as HTMLElement).closest(".tooltip-handle");
      if (!handle) return;
      tooltip.dataset.startMouseX = String(e.clientX);
      tooltip.dataset.startMouseY = String(e.clientY);
      tooltip.dataset.startLeft = tooltip.style.left;
      tooltip.dataset.startTop = tooltip.style.top;
      tooltip.dataset.dragging = "true";
    });
    document.addEventListener("mousemove", (e) => {
      if (tooltip.dataset.dragging !== "true") return;
      const dx = e.clientX - parseFloat(tooltip.dataset.startMouseX || "0");
      const dy = e.clientY - parseFloat(tooltip.dataset.startMouseY || "0");
      tooltip.style.left = (parseFloat(tooltip.dataset.startLeft || "0") + dx) + "px";
      tooltip.style.top = (parseFloat(tooltip.dataset.startTop || "0") + dy) + "px";
    });
    document.addEventListener("mouseup", () => {
      tooltip.dataset.dragging = "false";
    });
    tooltip.dataset.dragReady = "true";
  }

  const cx = canvas.width / 2,
    cy = canvas.height / 2;
  let nodes: db.Node[] = [];
  let edges: db.Edge[] = [];
  let zoom = 1;
  let panX = 0;
  let panY = 0;
  let isPanning = false;
  let panStartX = 0;
  let panStartY = 0;
  let panStartPanX = 0;
  let panStartPanY = 0;
  let isDrawingEdge = false;
  let edgeStartNode: db.Node | null = null;
  let currentMousePos = { x: 0, y: 0 };
  let highlightedEdgeIds: Set<number> = new Set();
  let highlightedPickupNodeId: number | null = null;
  let highlightedDropoffNodeId: number | null = null;

  const sx = (x: number) => x;
  const sy = (y: number) => y;

  const getTransform = () => {
    const tx = (x: number) => x * zoom + panX;
    const ty = (y: number) => y * zoom + panY;
    return { tx, ty };
  };

  const fromScreen = (sx: number, sy: number) => ({
    x: (sx - panX) / zoom,
    y: (sy - panY) / zoom,
  });

  const showTooltip = (x: number, y: number, html: string) => {
    tooltip.style.display = "block";
    tooltip.style.left = x + "px";
    tooltip.style.top = y + "px";
    tooltip.innerHTML = `<div class="tooltip-handle">⠿</div>\n${html}`;
  };

  const redrawCanvas = () => draw();

  const autoScale = () => {
    if (nodes.length === 0) return;
    let minX = Infinity,
      minY = Infinity,
      maxX = -Infinity,
      maxY = -Infinity;
    for (const n of nodes) {
      if (n.x_coord < minX) minX = n.x_coord;
      if (n.y_coord < minY) minY = n.y_coord;
      if (n.x_coord > maxX) maxX = n.x_coord;
      if (n.y_coord > maxY) maxY = n.y_coord;
    }
    const pad = 40;
    const rangeX = maxX - minX || 1;
    const rangeY = maxY - minY || 1;
    zoom = Math.min(
      (canvas.width - pad * 2) / rangeX,
      (canvas.height - pad * 2) / rangeY,
    );
    panX = (canvas.width - (minX + maxX) * zoom) / 2;
    panY = (canvas.height - (minY + maxY) * zoom) / 2;
  };

  const refreshNetwork = async () => {
    const data = await GetNetworkData();
    nodes = data.nodes;
    edges = data.edges;
    autoScale();
  };

  function setHighlightedRoute(
    edgeIds: number[],
    pickupNodeId: number,
    dropoffNodeId: number,
  ) {
    highlightedEdgeIds = new Set(edgeIds);
    highlightedPickupNodeId = pickupNodeId;
    highlightedDropoffNodeId = dropoffNodeId;
    draw();
  }

  const draw = () => {
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const { tx, ty } = getTransform();

    for (const edge of edges) {
      const sn = nodes.find((n) => n.id === edge.node_a_id);
      const en = nodes.find((n) => n.id === edge.node_b_id);
      if (!sn || !en) continue;
      if (highlightedEdgeIds.has(edge.id)) {
        ctx.strokeStyle = "#b9c2fa";
        ctx.lineWidth = 2;
      } else {
        ctx.strokeStyle = "#555";
        ctx.lineWidth = 1;
      }
      ctx.beginPath();
      ctx.moveTo(tx(sn.x_coord), ty(sn.y_coord));
      ctx.lineTo(tx(en.x_coord), ty(en.y_coord));
      ctx.stroke();
    }

    for (const node of nodes) {
      const x = tx(node.x_coord);
      const y = ty(node.y_coord);
      if (highlightedPickupNodeId === node.id) {
        ctx.fillStyle = "#5b2c6e";
      } else if (highlightedDropoffNodeId === node.id) {
        ctx.fillStyle = "#5b2c6e";
      } else {
        ctx.fillStyle = "#3498db";
      }
      ctx.beginPath();
      ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "#aaa";
      ctx.font = "10px monospace";
      ctx.fillText(node.label, x + 8, y - 6);
    }

    if (isDrawingEdge && edgeStartNode) {
      ctx.strokeStyle = "#e67e22";
      ctx.lineWidth = 2;
      ctx.setLineDash([5, 3]);
      ctx.beginPath();
      ctx.moveTo(tx(edgeStartNode.x_coord), ty(edgeStartNode.y_coord));
      ctx.lineTo(currentMousePos.x, currentMousePos.y);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  };

  const renderOrderItem = (o: main.OrderInfo) =>
    `<div class="order-item" data-order-id="${o.id}">
      <div class="order-item-header">
        <span class="order-id">#${o.id}</span>
        <span class="status-pill ${o.status.toLowerCase().replace(/\s+/g, "-")}">${o.status}</span>
      </div>
      <div class="order-item-body">
        <span><strong>Customer:</strong> ${o.customer_name || "—"}</span>
        <span><strong>Weight:</strong> ${o.weight} kg</span>
        <span><strong>Date:</strong> ${o.order_date ? o.order_date.slice(0, 10) : "—"}</span>
      </div>
    </div>`;

  const renderOrderRows = (orders: main.OrderInfo[]) =>
    orders.length > 0
      ? orders.map((o) => renderOrderItem(o)).join("")
      : "<p class='muted'>No orders found.</p>";

  const openNodeModal = (
    node: db.Node | null,
    clickX?: number,
    clickY?: number,
  ) => {
    let overlay = document.getElementById("node-modal-overlay");
    if (!overlay) {
      const div = document.createElement("div");
      div.innerHTML = `<div id="node-modal-overlay" class="modal-overlay" style="display:flex;"><div class="modal-content" id="node-modal-body"></div></div>`;
      document.body.appendChild(div.firstElementChild!);
    }
    overlay = document.getElementById("node-modal-overlay")!;
    const overlayEl = overlay;
    const body = document.getElementById("node-modal-body")!;
    const isNew = !node;

    const xVal = node ? node.x_coord : clickX || cx;
    const yVal = node ? node.y_coord : clickY || cy;
    const labelVal = node ? node.label : "";

    body.innerHTML = `
        <h3>${isNew ? "Add Node" : `Edit: ${node!.label}`}</h3>
        <div class="modal-form">
          <label>
            Label
            <input id="modal-node-label" class="auth-input" type="text" value="${labelVal}" placeholder="Node name" />
          </label>
          <label>
            X Coordinate
            <input id="modal-node-x" class="auth-input" type="number" step="0.01" value="${xVal}" />
          </label>
          <label>
            Y Coordinate
            <input id="modal-node-y" class="auth-input" type="number" step="0.01" value="${yVal}" />
          </label>
        </div>
        <div class="modal-actions">
          <button class="btn-primary" id="modal-node-save-btn">${isNew ? "Create" : "Save"}</button>
          ${isNew ? "" : `<button class="btn-danger" id="modal-node-delete-btn">Delete</button>`}
          <button class="btn-cancel" id="modal-node-cancel-btn">Cancel</button>
        </div>
        <p id="modal-node-error" class="error-msg" style="display:none;"></p>
      `;

    overlayEl.style.display = "flex";

    let nodeIsSaving = false;
    const nodeSaveBtn = document.getElementById(
      "modal-node-save-btn",
    ) as HTMLButtonElement;
    nodeSaveBtn?.addEventListener("click", async () => {
      if (nodeIsSaving) return;
      const labelInput = (
        document.getElementById("modal-node-label") as HTMLInputElement
      ).value.trim();
      const xInput = parseFloat(
        (document.getElementById("modal-node-x") as HTMLInputElement).value,
      );
      const yInput = parseFloat(
        (document.getElementById("modal-node-y") as HTMLInputElement).value,
      );
      const errEl = document.getElementById("modal-node-error")!;

      if (!labelInput) {
        errEl.textContent = "Label is required";
        errEl.style.display = "block";
        return;
      }
      if (isNaN(xInput) || isNaN(yInput)) {
        errEl.textContent = "Valid coordinates are required";
        errEl.style.display = "block";
        return;
      }

      errEl.style.display = "none";
      nodeIsSaving = true;
      nodeSaveBtn.disabled = true;
      nodeSaveBtn.textContent = isNew ? "Creating..." : "Saving...";
      try {
        if (isNew) {
          await CreateNode(xInput, yInput, labelInput);
        } else {
          await UpdateNode(node!.id, xInput, yInput, labelInput);
        }
        overlayEl.style.display = "none";
        tooltip.style.display = "none";
        await refreshNetwork();
        redrawCanvas();
      } catch (err: any) {
        errEl.textContent = err.message || err;
        errEl.style.display = "block";
      } finally {
        nodeIsSaving = false;
        nodeSaveBtn.disabled = false;
        nodeSaveBtn.textContent = isNew ? "Create" : "Save";
      }
    });

    document
      .getElementById("modal-node-delete-btn")
      ?.addEventListener("click", async () => {
        if (!confirm(`Delete node "${node!.label}"? This cannot be undone.`))
          return;
        const errEl = document.getElementById("modal-node-error")!;
        try {
          await DeleteNode(node!.id);
          overlayEl.style.display = "none";
          tooltip.style.display = "none";
          await refreshNetwork();
          redrawCanvas();
        } catch (err: any) {
          errEl.textContent = err.message || err;
          errEl.style.display = "block";
        }
      });

    document
      .getElementById("modal-node-cancel-btn")
      ?.addEventListener("click", () => {
        overlayEl.style.display = "none";
      });

    if (!overlay.dataset.listenerReady) {
      overlay.addEventListener("click", (e) => {
        if (e.target === overlayEl) overlayEl.style.display = "none";
      });
      overlay.dataset.listenerReady = "true";
    }
  };

  const openEdgeModal = (
    edge: db.Edge | null,
    pendingNodes?: { nodeAId: number; nodeBId: number } | null,
  ) => {
    let overlay = document.getElementById("edge-modal-overlay");
    if (!overlay) {
      const div = document.createElement("div");
      div.innerHTML = `<div id="edge-modal-overlay" class="modal-overlay" style="display:flex;"><div class="modal-content" id="edge-modal-body"></div></div>`;
      document.body.appendChild(div.firstElementChild!);
    }
    overlay = document.getElementById("edge-modal-overlay")!;
    const overlayEl = overlay;
    const body = document.getElementById("edge-modal-body")!;
    const isNew = !edge;

    let startNode: db.Node | null;
    let endNode: db.Node | null;
    let distanceVal: string;
    let speedVal: string;

    if (edge) {
      startNode = nodes.find((n) => n.id === edge.node_a_id) || null;
      endNode = nodes.find((n) => n.id === edge.node_b_id) || null;
      distanceVal = String(edge.distance_units);
      speedVal = String(edge.speed_limit);
    } else if (pendingNodes) {
      startNode = nodes.find((n) => n.id === pendingNodes.nodeAId) || null;
      endNode = nodes.find((n) => n.id === pendingNodes.nodeBId) || null;
      distanceVal = "";
      speedVal = "";
    } else {
      return;
    }

    const startLabel = startNode ? startNode.label : "Unknown";
    const endLabel = endNode ? endNode.label : "Unknown";

    body.innerHTML = `
        <h3>${isNew ? "Add Edge" : "Edit Edge"}</h3>
        <div class="modal-form">
          <label>
            Start Node
            <input class="auth-input" type="text" value="${startLabel}" readonly disabled />
          </label>
          <label>
            End Node
            <input class="auth-input" type="text" value="${endLabel}" readonly disabled />
          </label>
          <label>
            Distance (km)
            <input id="modal-edge-distance" class="auth-input" type="number" step="0.01" value="${distanceVal}" placeholder="e.g. 40" />
          </label>
          <label>
            Speed Limit (km/h)
            <input id="modal-edge-speed" class="auth-input" type="number" step="1" value="${speedVal}" placeholder="e.g. 50" />
          </label>
        </div>
        <div class="modal-actions">
          <button class="btn-primary" id="modal-edge-save-btn">${isNew ? "Create" : "Save"}</button>
          ${isNew ? "" : `<button class="btn-danger" id="modal-edge-delete-btn">Delete</button>`}
          <button class="btn-cancel" id="modal-edge-cancel-btn">Cancel</button>
        </div>
        <p id="modal-edge-error" class="error-msg" style="display:none;"></p>`;

    overlayEl.style.display = "flex";

    let edgeIsSaving = false;
    const edgeSaveBtn = document.getElementById(
      "modal-edge-save-btn",
    ) as HTMLButtonElement;
    edgeSaveBtn?.addEventListener("click", async () => {
      if (edgeIsSaving) return;
      const distanceInput = parseFloat(
        (document.getElementById("modal-edge-distance") as HTMLInputElement)
          .value,
      );
      const speedInput = parseFloat(
        (document.getElementById("modal-edge-speed") as HTMLInputElement).value,
      );
      const errEl = document.getElementById("modal-edge-error")!;

      if (isNaN(distanceInput) || distanceInput <= 0) {
        errEl.textContent = "Valid distance is required";
        errEl.style.display = "block";
        return;
      }
      if (isNaN(speedInput) || speedInput <= 0) {
        errEl.textContent = "Valid speed limit is required";
        errEl.style.display = "block";
        return;
      }

      errEl.style.display = "none";
      edgeIsSaving = true;
      edgeSaveBtn.disabled = true;
      edgeSaveBtn.textContent = isNew ? "Creating..." : "Saving...";
      try {
        if (isNew && pendingNodes) {
          await CreateEdge(
            pendingNodes.nodeAId,
            pendingNodes.nodeBId,
            distanceInput,
            speedInput,
          );
        } else if (edge) {
          await UpdateEdge(
            edge.id,
            edge.node_a_id,
            edge.node_b_id,
            distanceInput,
            speedInput,
          );
        }
        overlayEl.style.display = "none";
        tooltip.style.display = "none";
        await refreshNetwork();
        redrawCanvas();
      } catch (err: any) {
        errEl.textContent = err.message || err;
        errEl.style.display = "block";
      } finally {
        edgeIsSaving = false;
        edgeSaveBtn.disabled = false;
        edgeSaveBtn.textContent = isNew ? "Create" : "Save";
      }
    });

    document
      .getElementById("modal-edge-delete-btn")
      ?.addEventListener("click", async () => {
        if (!confirm("Delete this edge? This cannot be undone.")) return;
        const errEl = document.getElementById("modal-edge-error")!;
        try {
          await DeleteEdge(edge!.id);
          overlayEl.style.display = "none";
          tooltip.style.display = "none";
          await refreshNetwork();
          redrawCanvas();
        } catch (err: any) {
          errEl.textContent = err.message || err;
          errEl.style.display = "block";
        }
      });

    document
      .getElementById("modal-edge-cancel-btn")
      ?.addEventListener("click", () => {
        overlayEl.style.display = "none";
      });

    if (!overlay.dataset.listenerReady) {
      overlay.addEventListener("click", (e) => {
        if (e.target === overlayEl) overlayEl.style.display = "none";
      });
      overlay.dataset.listenerReady = "true";
    }
  };

  // --- Zoom / Pan Controls ---

  canvas.addEventListener(
    "wheel",
    (event) => {
      event.preventDefault();
      const rect = canvas.getBoundingClientRect();
      const mx = event.clientX - rect.left;
      const my = event.clientY - rect.top;

      const oldZoom = zoom;
      const factor = event.deltaY < 0 ? 1.15 : 0.85;
      const newZoom = Math.max(0.2, Math.min(10, oldZoom * factor));
      if (newZoom === oldZoom) return;

      // Zoom centered on mouse position
      const baseX = (mx - panX) / oldZoom;
      const baseY = (my - panY) / oldZoom;
      panX = mx - baseX * newZoom;
      panY = my - baseY * newZoom;
      zoom = newZoom;
      redrawCanvas();
    },
    { passive: false },
  );

  canvas.addEventListener("mousedown", (event) => {
    const rect = canvas.getBoundingClientRect();
    const mx = event.clientX - rect.left;
    const my = event.clientY - rect.top;
    const { tx, ty } = getTransform();

    let onNode = false;
    for (const node of nodes) {
      const dist = Math.sqrt(
        (mx - sx(tx(node.x_coord))) ** 2 + (my - sy(ty(node.y_coord))) ** 2,
      );
      if (dist < 12) {
        onNode = true;
        break;
      }
    }

    if (!onNode) {
      isPanning = true;
      panStartX = mx;
      panStartY = my;
      panStartPanX = panX;
      panStartPanY = panY;
      canvas.style.cursor = "grabbing";
    }
  });

  document.addEventListener("mousemove", (event) => {
    if (isPanning) {
      const rect = canvas.getBoundingClientRect();
      const mx = event.clientX - rect.left;
      const my = event.clientY - rect.top;
      panX = panStartPanX + (mx - panStartX);
      panY = panStartPanY + (my - panStartY);
      draw();
    }
  });

  document.addEventListener("mouseup", () => {
    if (isPanning) {
      isPanning = false;
      canvas.style.cursor = "crosshair";
    }
    if (isDrawingEdge) {
      isDrawingEdge = false;
      edgeStartNode = null;
      canvas.style.cursor = "crosshair";
      draw();
    }
  });

  document.getElementById("zoom-in-btn")!.addEventListener("click", () => {
    const newZoom = Math.min(10, zoom * 1.5);
    const cx = canvas.width / 2,
      cy = canvas.height / 2;
    const baseX = (cx - panX) / zoom;
    const baseY = (cy - panY) / zoom;
    panX = cx - baseX * newZoom;
    panY = cy - baseY * newZoom;
    zoom = newZoom;
    redrawCanvas();
  });

  document.getElementById("zoom-out-btn")!.addEventListener("click", () => {
    const newZoom = Math.max(0.2, zoom / 1.5);
    const cx = canvas.width / 2,
      cy = canvas.height / 2;
    const baseX = (cx - panX) / zoom;
    const baseY = (cy - panY) / zoom;
    panX = cx - baseX * newZoom;
    panY = cy - baseY * newZoom;
    zoom = newZoom;
    redrawCanvas();
  });

  document.getElementById("zoom-reset-btn")!.addEventListener("click", () => {
    zoom = 1;
    panX = 0;
    panY = 0;
    redrawCanvas();
  });

  canvas.addEventListener("dblclick", (event) => {
    if (!authStore.can("manage_nodes")) return;
    const rect = canvas.getBoundingClientRect();
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;

    const { tx, ty } = getTransform();
    let hitNode = false;
    for (const node of nodes) {
      const dist = Math.sqrt(
        (mouseX - sx(tx(node.x_coord))) ** 2 +
        (mouseY - sy(ty(node.y_coord))) ** 2,
      );
      if (dist < 12) {
        hitNode = true;
        break;
      }
    }
    if (!hitNode) {
      const { x, y } = fromScreen(mouseX, mouseY);
      openNodeModal(null, x, y);
    }
  });

  canvas.addEventListener("mousedown", async (event) => {
    if (!authStore.can("manage_edges")) return;
    const rect = canvas.getBoundingClientRect();
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;

    const { tx, ty } = getTransform();
    let foundNode: db.Node | null = null;

    for (const node of nodes) {
      const dist = Math.sqrt(
        (mouseX - sx(tx(node.x_coord))) ** 2 +
        (mouseY - sy(ty(node.y_coord))) ** 2,
      );
      if (dist < 12) {
        foundNode = node;
        break;
      }
    }

    if (foundNode) {
      isDrawingEdge = true;
      edgeStartNode = foundNode;
    }
  });

  canvas.addEventListener("mousemove", async (event) => {
    if (!authStore.can("manage_edges")) return;
    const rect = canvas.getBoundingClientRect();
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;

    if (isDrawingEdge && edgeStartNode) {
      currentMousePos = { x: mouseX, y: mouseY };
      requestAnimationFrame(draw);
    }
  });

  canvas.addEventListener("mouseup", async (event) => {
    if (!authStore.can("manage_edges")) return;
    if (!isDrawingEdge || !edgeStartNode) return;
    const rect = canvas.getBoundingClientRect();
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;

    const { tx, ty } = getTransform();
    let foundNode: db.Node | null = null;

    for (const node of nodes) {
      const dist = Math.sqrt(
        (mouseX - sx(tx(node.x_coord))) ** 2 +
        (mouseY - sy(ty(node.y_coord))) ** 2,
      );
      if (dist < 12 && node.id != edgeStartNode!.id) {
        foundNode = node;
        break;
      }
    }

    if (foundNode) {
      tooltip.style.display = "none";
      openEdgeModal(null, {
        nodeAId: edgeStartNode!.id,
        nodeBId: foundNode.id,
      });
    }
    isDrawingEdge = false;
    edgeStartNode = null;
    canvas.style.cursor = "crosshair";
    requestAnimationFrame(draw);
  });

  canvas.addEventListener("click", async (event) => {
    if (isDrawingEdge) return;
    const rect = canvas.getBoundingClientRect();
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;

    const { tx, ty } = getTransform();
    let foundNode: db.Node | null = null;
    let foundEdge: db.Edge | null = null;

    for (const node of nodes) {
      const dist = Math.sqrt(
        (mouseX - sx(tx(node.x_coord))) ** 2 +
        (mouseY - sy(ty(node.y_coord))) ** 2,
      );
      if (dist < 12) {
        foundNode = node;
        break;
      }
    }

    if (!foundNode) {
      for (const edge of edges) {
        const n1 = nodes.find((n) => n.id === edge.node_a_id);
        const n2 = nodes.find((n) => n.id === edge.node_b_id);
        if (n1 && n2) {
          const d = distToSegment(
            mouseX,
            mouseY,
            sx(tx(n1.x_coord)),
            sy(ty(n1.y_coord)),
            sx(tx(n2.x_coord)),
            sy(ty(n2.y_coord)),
          );
          if (d < 5) {
            foundEdge = edge;
            break;
          }
        }
      }
    }

    if (foundNode) {
      const node: db.Node = foundNode;
      const detail = await GetNodeDetails(node.id);

      const revenueHtml =
        authStore.can("view_financials") && detail.total_revenue > 0
          ? `<div class="stats-revenue">Total Revenue: $${detail.total_revenue.toFixed(2)}</div>`
          : "";

      showTooltip(
        sx(tx(foundNode.x_coord)),
        sy(ty(foundNode.y_coord)),
        `
        <div class="node-popup">
            <h3>${foundNode.label}</h3>
            ${revenueHtml}
            
            <div class="filter-tabs">
                <button class="tab-btn active" id="tab-pending">Active (${detail.pending_orders?.length || 0})</button>
                <button class="tab-btn" id="tab-completed">History (${detail.completed_orders?.length || 0})</button>
            </div>

            <div id="orders-container" class="orders-list">
                ${renderOrderRows(detail.pending_orders || [])}
            </div>

            ${authStore.can("manage_nodes") ? `<button class="btn-primary mt-2" style="width:100%" id="manage-node-btn">Manage Node</button>` : ""}
            <button class="btn-secondary mt-2" style="width:100%" id="view-all-orders-btn">View All Orders →</button>
        </div>
        `,
      );
      // Event delegation for order hover highlighting (works across tab switches)
      if (!tooltip.dataset.listenerReady) {
        tooltip.addEventListener("mouseover", async (e) => {
          const el = (e.target as HTMLElement).closest(
            ".order-item[data-order-id]",
          );
          if (!el) return;
          const oid = Number((el as HTMLElement).dataset.orderId);
          if (isNaN(oid)) return;
          try {
            const edgeIds = await GetOrderRouteEdgeIds(oid);
            setHighlightedRoute(edgeIds, 0, 0);
          } catch {}
        });

        tooltip.addEventListener("mouseout", (e) => {
          const related = (e as MouseEvent).relatedTarget as HTMLElement | null;
          if (
            related &&
            tooltip.contains(related) &&
            related.closest(".order-item[data-order-id]")
          )
            return;
          highlightedEdgeIds = new Set();
          highlightedPickupNodeId = null;
          highlightedDropoffNodeId = null;
          draw();
        });

        tooltip.dataset.listenerReady = "true";
      }

      document.getElementById("tab-pending")?.addEventListener("click", (e) => {
        e.stopPropagation();
        toggleTabs("pending", detail, renderOrderRows);
      });
      document
        .getElementById("tab-completed")
        ?.addEventListener("click", (e) => {
          e.stopPropagation();
          toggleTabs("completed", detail, renderOrderRows);
        });
      document
        .getElementById("manage-node-btn")
        ?.addEventListener("click", (e) => {
          e.stopPropagation();
          tooltip.style.display = "none";
          openNodeModal(node);
        });
      document
        .getElementById("view-all-orders-btn")
        ?.addEventListener("click", (e) => {
          e.stopPropagation();
          tooltip.style.display = "none";
          document
            .querySelectorAll(".nav-btn")
            .forEach((b) => b.classList.remove("active"));
          document.getElementById("nav-orders")?.classList.add("active");
          const titleEl = document.getElementById("view-title");
          const container = document.getElementById("view-container");
          if (titleEl) titleEl.innerText = "Order Management";
          if (container)
            container.innerHTML = `<div id="view-container-inner"></div>`;
          renderOrdersView();
        });
    } else if (foundEdge) {
      const edge: db.Edge = foundEdge;
      showTooltip(
        mouseX,
        mouseY,
        `<strong>Edge</strong><br>
         Distance: ${edge.distance_units} km<br>
         Speed Limit: ${edge.speed_limit} km/h
          ${authStore.can("manage_edges") ? `<button class="btn-primary mt-2" style="width:100%" id="manage-edge-btn">Manage Edge</button>` : ""}`,
      );
      document
        .getElementById("manage-edge-btn")
        ?.addEventListener("click", (e) => {
          e.stopPropagation();
          tooltip.style.display = "none";
          openEdgeModal(edge);
        });
    } else {
      tooltip.style.display = "none";
    }
  });

  await refreshNetwork();
  draw();
};

const distToSegment = (
  px: number,
  py: number,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
) => {
  const l2 = (x1 - x2) ** 2 + (y1 - y2) ** 2;
  if (l2 === 0) return Math.sqrt((px - x1) ** 2 + (py - y1) ** 2);
  let t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.sqrt(
    (px - (x1 + t * (x2 - x1))) ** 2 + (py - (y1 + t * (y2 - y1))) ** 2,
  );
};

const toggleTabs = (
  type: "pending" | "completed",
  detail: any,
  renderer: Function,
) => {
  const container = document.getElementById("orders-container");
  const pBtn = document.getElementById("tab-pending");
  const cBtn = document.getElementById("tab-completed");

  if (!container || !pBtn || !cBtn) return;

  if (type === "pending") {
    container.innerHTML = renderer(detail.pending_orders || []);
    pBtn.classList.add("active");
    cBtn.classList.remove("active");
  } else {
    container.innerHTML = renderer(detail.completed_orders || []);
    cBtn.classList.add("active");
    pBtn.classList.remove("active");
  }
};
