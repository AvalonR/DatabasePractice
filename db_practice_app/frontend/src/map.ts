import { GetNetworkData, GetNodeDetails } from "../wailsjs/go/main/App";
import { db } from "../wailsjs/go/models";
import { main } from "../wailsjs/go/models";
import { authStore } from "./auth";

export const initMap = async (containerId: string) => {
  const container = document.getElementById(containerId);
  if (!container) return;

  container.innerHTML = `
        <div style="position: relative;">
            <canvas id="mapCanvas" width="800" height="600" style="border:1px solid #444; background: #222; cursor: crosshair;"></canvas>
            <div id="map-tooltip" style="display: none; position: absolute; background: #333; color: white; padding: 12px; border-radius: 8px; border: 1px solid #555; pointer-events: none; z-index: 100; box-shadow: 0 4px 15px rgba(0,0,0,0.5); min-width: 150px;"></div>
        </div>
    `;

  const canvas = document.getElementById("mapCanvas") as HTMLCanvasElement;
  const tooltip = document.getElementById("map-tooltip")!;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const data = await GetNetworkData();

  const cx = canvas.width / 2;
  const cy = canvas.height / 2;
  const maxRadius = Math.sqrt(cx ** 2 + cy ** 2);

  let waveRadius = 0;
  const waveSpeed = 2;

  const draw = () => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.strokeStyle = "rgba(52, 152, 219, 0.2)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(cx, cy, waveRadius, 0, Math.PI * 2);
    ctx.stroke();

    data.edges.forEach((edge: db.Edge) => {
      const start = data.nodes.find((n) => n.id === edge.node_a_id);
      const end = data.nodes.find((n) => n.id === edge.node_b_id);

      if (start && end) {
        const midX = (start.x_coord + end.x_coord) / 2;
        const midY = (start.y_coord + end.y_coord) / 2;
        const distFromCenter = Math.sqrt((midX - cx) ** 2 + (midY - cy) ** 2);

        if (waveRadius > distFromCenter) {
          const edgeProgress = Math.min(1, (waveRadius - distFromCenter) / 100);

          const currentX =
            start.x_coord + (end.x_coord - start.x_coord) * edgeProgress;
          const currentY =
            start.y_coord + (end.y_coord - start.y_coord) * edgeProgress;

          ctx.strokeStyle = "#555";
          ctx.beginPath();
          ctx.moveTo(start.x_coord, start.y_coord);
          ctx.lineTo(currentX, currentY);
          ctx.stroke();

          if (edgeProgress > 0.8) {
            ctx.globalAlpha = (edgeProgress - 0.8) * 5;
            ctx.fillStyle = "rgba(0,0,0,0.6)";
            ctx.fillRect(midX - 2, midY - 10, 45, 15);
            ctx.fillStyle = "#2ecc71";
            ctx.fillText(`${edge.distance_units}km`, midX, midY);
            ctx.globalAlpha = 1;
          }
        }
      }
    });

    data.nodes.forEach((node: db.Node) => {
      const distFromCenter = Math.sqrt(
        (node.x_coord - cx) ** 2 + (node.y_coord - cy) ** 2,
      );

      if (waveRadius > distFromCenter) {
        const nodeProgress = Math.min(1, (waveRadius - distFromCenter) / 50);

        ctx.globalAlpha = nodeProgress;
        ctx.fillStyle = "#3498db";
        ctx.beginPath();
        ctx.arc(node.x_coord, node.y_coord, 8 * nodeProgress, 0, Math.PI * 2);
        ctx.fill();

        ctx.strokeStyle = "white";
        ctx.stroke();

        ctx.fillStyle = "white";
        ctx.fillText(node.label, node.x_coord + 12, node.y_coord - 12);
        ctx.globalAlpha = 1;
      }
    });

    if (waveRadius < maxRadius + 100) {
      waveRadius += waveSpeed;
      requestAnimationFrame(draw);
    }
  };

  canvas.addEventListener("click", async (event) => {
    const rect = canvas.getBoundingClientRect();
    const mouseX = event.clientX - rect.left;
    const mouseY = event.clientY - rect.top;

    let foundNode: db.Node | null = null;
    let foundEdge: db.Edge | null = null;

    for (const node of data.nodes) {
      const dist = Math.sqrt(
        (mouseX - node.x_coord) ** 2 + (mouseY - node.y_coord) ** 2,
      );
      if (dist < 12) {
        foundNode = node;
        break;
      }
    }

    if (!foundNode) {
      for (const edge of data.edges) {
        const n1 = data.nodes.find((n) => n.id === edge.node_a_id);
        const n2 = data.nodes.find((n) => n.id === edge.node_b_id);
        if (n1 && n2) {
          const d = distToSegment(
            mouseX,
            mouseY,
            n1.x_coord,
            n2.x_coord,
            n1.y_coord,
            n2.y_coord,
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

      const renderOrderRows = (orders: main.OrderInfo[]) =>
        orders.length > 0
          ? orders
            .map(
              (o) => `
                <div class="order-item">
                    <span>#${o.id}</span>
                    <span class="status-pill ${o.status.toLowerCase().replace(" ", "-")}">${o.status}</span>
                    <span>${o.weight}kg</span>
                </div>`,
            )
            .join("")
          : "<p class='muted'>No orders found.</p>";

      showTooltip(
        foundNode.x_coord,
        foundNode.y_coord,
        `
        <div class="node-popup">
            <h3>${foundNode.label}</h3>
            
            <div class="filter-tabs">
                <button class="tab-btn active" id="tab-pending">Active (${detail.pending_orders?.length || 0})</button>
                <button class="tab-btn" id="tab-completed">History (${detail.completed_orders?.length || 0})</button>
            </div>

            <div id="orders-container" class="orders-list">
                ${renderOrderRows(detail.pending_orders || [])}
            </div>

            ${authStore.can("edit_nodes") ? `<button class="btn-primary mt-2" style="width:100%">Manage Node</button>` : ""}
        </div>
        `,
      );
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
    } else if (foundEdge) {
      const edge: db.Edge = foundEdge;
      showTooltip(
        mouseX,
        mouseY,
        `<strong>Route Link</strong><br>
         Distance: ${edge.distance_units} km<br>
         Speed Limit: ${edge.speed_limit} km/h`,
      );
    } else {
      tooltip.style.display = "none";
    }
  });

  const showTooltip = (x: number, y: number, content: string) => {
    tooltip.style.display = "block";
    tooltip.style.left = `${x + 15}px`;
    tooltip.style.top = `${y - 15}px`;
    tooltip.innerHTML = content;
  };

  // function openEditNodeModal(node: db.Node, nodeStats: number) {
  //   showTooltip(
  //     node.x_coord,
  //     node.y_coord,
  //     `<strong>${node.label}</strong><br>
  //         ID: ${node.id}<br>
  //         Location: ${node.x_coord}, ${node.y_coord}<br>
  //         Pending Orders: ${nodeStats}`,
  //   );
  // }

  draw();
};

const distToSegment = (
  px: number,
  py: number,
  x1: number,
  x2: number,
  y1: number,
  y2: number,
) => {
  const l2 = (x1 - x2) ** 2 + (y1 - y2) ** 2;
  if (l2 === 0) return Math.sqrt((px - x1) ** 2 + (py - py) ** 2);
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
