# Wayanad Disaster Digital Twin

Full-stack educational digital twin for **Problem 3: Disaster Area Digital Twin**. It simulates **flood / debris inundation** and **slope (landslide) Factor of Safety** on a schematic DEM of the **Chooralmala–Mundakkai–Meppadi** corridor in Wayanad, Kerala, using the **July 2024** extreme-rainfall disaster as the reference event.

This is **not** an official IMD, NDMA, or Kerala SDMA product. Terrain is schematic (Western Ghats–shaped), not a Survey of India DEM or forensic reconstruction.

## Stack

- Frontend: React + Vite + TypeScript + Tailwind + Leaflet + react-three-fiber
- Backend: FastAPI + NumPy (`POST /api/simulate`, scenarios JSON store)

## Run locally

Terminal 1 — API:

```powershell
cd backend
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 8000
```

Terminal 2 — UI:

```powershell
cd frontend
npm install --legacy-peer-deps
npm run dev
```

Open [http://localhost:5173](http://localhost:5173). Vite proxies `/api` to port 8000.

## Judge demo path

1. Landing — Wayanad 2024 dual-hazard story.
2. **Twin console** — OSM map of the corridor; **Pre-monsoon** vs **July 2024 analogue**; move rainfall / saturation sliders; **Run twin**; switch Combined / Flood / Slope layers; check hamlet KPIs.
3. **3D twin** — orbit the heightmap colored by risk.
4. **Compare** — baseline vs July 2024 analogue side by side.
5. **Methodology** — FoS + flood notes and disclaimer.

## Models (short)

- **Slope:** infinite-slope FoS; pore pressure rises with saturation and storm rainfall.
- **Flood:** land-cover runoff plus bathtub fill along the valley river / debris path.
- **Combined:** max of the two layers plus a small interaction term.

Population and road-cut KPIs are illustrative counts on labeled cells, not census microdata.
