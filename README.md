# Room Scanner

An iPhone app that scans a room with LiDAR and gives you:

- a **3D model** (OBJ and STL, for Fusion 360)
- the **raw LiDAR mesh** (OBJ and STL)
- a **floor plan** (DXF, opens as a sketch in Fusion 360)
- **measurements** (on screen and as a CSV file)

Needs an iPhone or iPad with LiDAR (Pro models) and iOS 17 or newer.

## Run it on your iPhone

1. Open `RoomScanner.xcodeproj` in Xcode (16 or newer).
2. Click the **RoomScanner** project, then the **RoomScanner** target, then **Signing & Capabilities**.
3. Pick your **Team** (your Apple ID). If Xcode says the bundle ID is taken, change `com.vonmann.roomscanner` to something unique.
4. Plug in your iPhone, pick it at the top of Xcode, and press **Run** (▶).
5. First time only: on the iPhone, go to **Settings > General > VPN & Device Management** and trust your developer profile. Also turn on **Developer Mode** if asked.

If the project ever won't open, run `brew install xcodegen && xcodegen` in this folder to rebuild it from `project.yml`.

## Scanning tips for best accuracy

- Good, even light. Close blinds if sun is shining straight in.
- Walk slowly around the room. Point at every wall, corner, door and window.
- Stay about 1 to 3 m (3 to 10 ft) from the walls.
- Then use **Check with a tape measure** on a long wall. The app fixes any scale error in all numbers and exports.

## Using the files in Fusion 360

| File | How to open in Fusion 360 |
| --- | --- |
| `*_floor_plan.dxf` | **Insert > Insert DXF**. Pick a plane. You get a sketch you can extrude. |
| `*_model.obj` / `*_model.stl` | **Insert > Insert Mesh**. Pick the same units you exported in. |
| `*_lidar_mesh.obj` / `.stl` | **Insert > Insert Mesh**. Large file. Good for tracing details. |
| `*_measurements.csv` | Open in Numbers, Excel or Google Sheets. |

Exports use the units you choose in the app (mm by default) and Z axis up, which is Fusion's default.

The 3D room model is built from clean boxes: walls are pushed **outward** by the wall thickness, so the inside faces stay exactly where they were scanned.

## How it works

- `RoomScanner/Scanning` - Apple **RoomPlan** finds walls, doors, windows and furniture. We give it our own ARKit session so we can also save the raw LiDAR mesh.
- `RoomScanner/Models` - saved scans (in the app's Documents folder, also visible in the Files app), room geometry, and measurements.
- `RoomScanner/Export` - OBJ, STL, DXF and CSV writers.
- `RoomScanner/Views` - list of scans, floor plan, measurements, accuracy check, and export screen.
