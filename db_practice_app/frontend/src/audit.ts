import { GetAuditLogs } from "../wailsjs/go/main/App";
import { main } from "../wailsjs/go/models";

export const renderAuditView = async () => {
  const container = document.getElementById("view-container");
  if (!container) return;

  container.innerHTML = `
    <div class="users-toolbar">
      <h2>System Audit Logs</h2>
    </div>
    <div id="auditWrap" class="users-table-wrap">
      <div class="loading-spinner">Loading audit logs...</div>
    </div>
  `;

  try {
    const logs = await GetAuditLogs();
    renderAuditLogs(logs);
  } catch (err) {
    const wrap = document.getElementById("auditWrap");
    if (wrap) wrap.innerHTML = `<p class="error-msg">Failed to load audit logs: ${err}</p>`;
  }

  document.getElementById("auditRefreshBtn")?.addEventListener("click", () => {
    renderAuditView();
  });
};

const renderAuditLogs = (logs: main.AuditLogEntry[]) => {
  const wrap = document.getElementById("auditWrap");
  if (!wrap) return;

  if (logs.length === 0) {
    wrap.innerHTML = '<p class="muted">No audit entries found.</p>';
    return;
  }

  wrap.innerHTML = `
    <div class="users-count" style="margin-bottom:0.75rem;">${logs.length} entries</div>
    <div class="audit-timeline">
      ${logs
        .map(
          (e) => `
        <div class="timeline-item">
          <div class="timeline-dot"></div>
          <div class="timeline-body">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:2px;">
              <strong>${escapeHtml(e.username)}</strong>
              <span class="timeline-time">${new Date(e.timestamp).toLocaleString()}</span>
            </div>
            <div class="timeline-action">${escapeHtml(e.action)}</div>
          </div>
        </div>
      `,
        )
        .join("")}
    </div>
  `;
};

function escapeHtml(s: string): string {
  const div = document.createElement("div");
  div.textContent = s;
  return div.innerHTML;
}
