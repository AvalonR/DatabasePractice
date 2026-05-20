# Delivery Network Management System

A university database practice project — a delivery/logistics network managed through MySQL 8.0+ with a Wails v2 desktop application (Go + Vanilla TypeScript). The system models a complete delivery ecosystem: map regions, nodes, edges, vehicles, staff, customers, orders, routes, deliveries, and role-based user access.

## Project Structure

```
├── docs/
│   ├── db_schema/
│   │   ├── schema.sql              # 18-table schema
│   │   ├── filled_schema.sql       # Schema + 130+ records per table
│   │   ├── queries.sql             # 30 executable SQL queries
│   │   ├── migration.sql           # Schema migration + audit triggers
│   │   ├── ai_prompts.md           # Prompts used for bulk data generation
│   │   └── seed.sql                # Minimal seed (1 route)
│   ├── diagrams/
│   │   ├── er_diagram.png
│   │   ├── normalization_diagram.png
│   │   └── implementation_diagram.png
│   ├── generate_routes.py          # Dijkstra shortest-path route generator
│   ├── Report.docx                 # Full project report
│   └── Presentation.pptx           # Project presentation
├── db_practice_app/                # Wails v2 desktop application
│   ├── main.go                     # Entry point
│   ├── app.go                      # App struct, startup, auth
│   ├── route.go                    # Dijkstra pathfinding, route APIs
│   ├── orders.go                   # Order/dispatch logic
│   ├── nodes.go                    # Node/edge CRUD
│   ├── fleet.go                    # Vehicle/staff management
│   ├── users.go                    # User management
│   ├── audit_logs.go              # Audit log queries
│   ├── auth.go                     # Authentication
│   ├── db/                         # MySQL connection init
│   └── frontend/src/               # TypeScript UI
│       ├── map.ts                  # Map canvas, tooltips, highlighting
│       ├── orders.ts              # Orders page, route details, minimap
│       ├── auth.ts                 # Login/register
│       └── style.css              # Full app styling
├── check.py                        # Deliverables verification script
└── README.md
```

## Database

- **18 tables**: `map_regions`, `nodes`, `edges`, `locations`, `customers`, `staff`, `permissions`, `roles`, `role_permissions`, `users`, `vehicle_types`, `vehicles`, `orders`, `routes`, `route_segments`, `deliveries`, `maintenance_logs`, `system_audit_logs`
- **3 triggers**: audit logs on delivery status changes, order creation, order updates
- **Data sections**:
  - Section A — 10 manually crafted records per table
  - Section B — 10 records per table transferred via `INSERT INTO ... SELECT`
  - Section C — 100+ AI-generated records per table
- **30 SQL queries**: basic, substring/date, joins (2-6 tables), nested subqueries, set operations, DML, views, analytical
- Route paths computed via **Dijkstra's shortest-path algorithm** using edge `distance_units`

## Desktop Application

Built with **Wails v2** (Go backend, Vanilla TypeScript frontend, HTML5 Canvas).

- **Map view** — Render nodes/edges on a draggable, zoomable canvas
- **Route highlighting** — Click a delivery to highlight its path on the map
- **Order management** — Create orders, dispatch vehicles, assign drivers
- **Role-based access** — Admin, Manager, Dispatcher, Driver, Customer with granular permissions
- **Tooltip dragging** — Drag the handle bar on delivery tooltips
- **Minimap** — Delivery route preview on the orders page

## Prerequisites

- [MySQL](https://dev.mysql.com/downloads/) 8.0+
- [Go](https://go.dev/dl/) 1.21+
- [Node.js](https://nodejs.org/) 18+
- [Wails CLI](https://wails.io/docs/gettingstarted/installation) v2
- [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (included on Windows 10 1803+ / Windows 11)

## Setup

```bash
# 1. Create and populate the database
mysql -u root -p < docs/db_schema/schema.sql
mysql -u root -p delivery_system < docs/db_schema/filled_schema.sql

# 2. Run the application (development mode)
cd db_practice_app
wails dev

# 3. Build a standalone .exe
wails build -platform windows/amd64
```

## Building for Distribution

```bash
wails build -platform windows/amd64 -o delivery_app.exe
```

Produces a single `.exe` in `build/bin/` — no runtime dependencies beyond WebView2.

## Documentation

- **Report**: `docs/Report.docx` — full project documentation
- **Presentation**: `docs/Presentation.pptx`
- **SQL Queries**: `docs/db_schema/queries.sql` — 30 tested queries
- **AI Prompts**: `docs/db_schema/ai_prompts.md` — prompts used for bulk data generation
- **Diagrams**: `docs/diagrams/` — ER, normalization, implementation diagrams

## Author

Roman Kysliak — Database Practice Project, 2026
