import { GetNetworkData, GetNodeStats } from "../wailsjs/go/main/App";
import { db } from "../wailsjs/go/models";

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

  let progress = 0;
  const speed = 0.015;

  const draw = () => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    data.edges.forEach((edge: db.Edge) => {
      const start = data.nodes.find((n: db.Node) => n.id === edge.node_a_id);
      const end = data.nodes.find((n: db.Node) => n.id === edge.node_b_id);

      if (start && end) {
        const currentX =
          start.x_coord + (end.x_coord - start.x_coord) * progress;
        const currentY =
          start.y_coord + (end.y_coord - start.y_coord) * progress;

        ctx.strokeStyle = "#555";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(start.x_coord, start.y_coord);
        ctx.lineTo(currentX, currentY);
        ctx.stroke();

        if (progress > 0.8) {
          const midX = (start.x_coord + end.x_coord) / 2;
          const midY = (start.y_coord + end.y_coord) / 2;
          ctx.fillStyle = "rgba(0,0,0,0.6)";
          ctx.fillRect(midX - 15, midY - 10, 30, 15);
          ctx.fillStyle = "#2ecc71";
          ctx.font = "12px Arial";
          ctx.textAlign = "center";
          ctx.fillText(`${edge.distance_units}km`, midX, midY);
          ctx.globalAlpha = 1;
        }
      }
    });

    data.nodes.forEach((node: db.Node) => {
      ctx.globalAlpha = progress;
      ctx.fillStyle = "#3498db";
      ctx.beginPath();
      ctx.arc(node.x_coord, node.y_coord, 8, 0, Math.PI * 2);
      ctx.fill();

      ctx.strokeStyle = "white";
      ctx.lineWidth = 1;
      ctx.stroke();

      ctx.fillStyle = "white";
      ctx.font = "bold 12px Arial";
      ctx.textAlign = "left";
      ctx.fillText(node.label, node.x_coord + 12, node.y_coord - 12);
      ctx.globalAlpha = 1;
    });

    if (progress < 1) {
      progress += speed;
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
      const nodeStats = await GetNodeStats(node.id);

      showTooltip(
        node.x_coord,
        node.y_coord,
        `<strong>${node.label}</strong><br>
         ID: ${node.id}<br>
         Location: ${node.x_coord}, ${node.y_coord}<br>
         Pending Orders: ${nodeStats}`,
      );
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
