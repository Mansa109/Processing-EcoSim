// ============================================================
//  EcoSim – world.pde
//  World: entity collections, update loop, rendering helpers,
//  reproduction, population graph, HUD.
// ============================================================

// ── Global population caps ────────────────────────────────────
final int MAX_HERBIVORES = 120;
final int MAX_CARNIVORES = 50;   // combined across both lairs
final int MAX_CORPSES    = 30;
final int GRAPH_HISTORY  = 300;

// Herbivore edge-spawn threshold
final int HERB_SPAWN_THRESHOLD = 30;  // below this, edges start spawning

// Terrain type constants (must stay accessible to all .pde files)
final int GRASSLAND = 0;
final int BRUSH     = 1;
final int WATER     = 2;
final int ROCK      = 3;

// ── Lair hibernate / roam parameters ─────────────────────────
// Predators return to lair when energy > this fraction of maxEnergy
final float HIBERNATE_RETURN_THRESHOLD = 0.85;
// They hibernate until energy drops to this fraction
final float HIBERNATE_EXIT_THRESHOLD   = 0.45;
// Roam radius at HIBERNATE_EXIT_THRESHOLD energy (world units)
final float ROAM_RADIUS_MIN  = 20;
// Roam radius when nearly dead (energy → 0)
final float ROAM_RADIUS_MAX  = 80;

class World {
  int worldWidth;
  int worldHeight;
  PVector worldSize;
  int gridSize;

  int[][] terrain;

  ArrayList<Creature> herbivores;
  ArrayList<Creature> carnivores;
  ArrayList<PVector>  plants;
  Camera camera;

  boolean showRanges = false;
  boolean paused     = false;

  // terrain palette
  color grassColor = color(134, 180,  80);
  color brushColor = color(107, 142,  60);
  color waterColor = color( 70, 130, 180);
  color rockColor  = color(160, 145, 120);

  // ── Two lairs ─────────────────────────────────────────────────
  PVector[] lairCenters;
  float lairRadius         = 18;
  float lairRestRadius     = 10;
  int   maxLairResidents   = 5;

  // Allegiance colours: [lair0, lair1] – low-energy / high-energy pair
  color[] lairColorLow  = { color(100, 30, 30),  color(120, 80, 30)  };
  color[] lairColorHigh = { color(230, 80, 80),  color(230, 160, 80) };
  color[] lairHudColor  = { color(210, 80, 80),  color(220, 160, 30) };

  // Guard posts (2 per lair)
  PVector[][] guardPosts;

  // plant regrowth
  int   plantCap       = 60;
  int   regrowInterval = 120;
  int   regrowCounter  = 0;
  boolean showGraph    = true;

  // Birth / spawn counters for HUD
  int herbBirths  = 0;
  int carnBirths  = 0;
  int herbEdgeSpawns = 0;

  // Pending offspring
  ArrayList<Creature> pendingHerbivores;
  ArrayList<Creature> pendingCarnivores;

  // Population history
  int[] herbHistory;
  int[] carnHistory;
  int   historyHead = 0;

  // ── Manual spawn state ────────────────────────────────────────
  // 0 = herbivore, 1 = carnivore
  int spawnType = 0;
  String[] spawnTypeNames = { "Herbivore", "Carnivore" };

  // ── Constructor ───────────────────────────────────────────────
  World(int widthUnits, int heightUnits, int unitSize,
        int herbivoreCount, int carnivoreCount, int plantCount,
        int cameraWidthUnits, int cameraHeightUnits) {

    gridSize    = unitSize;
    worldWidth  = widthUnits;
    worldHeight = heightUnits;
    worldSize   = new PVector(worldWidth, worldHeight);

    terrain = new int[worldWidth][worldHeight];
    generateTerrain();

    herbivores        = new ArrayList<Creature>();
    carnivores        = new ArrayList<Creature>();
    plants            = new ArrayList<PVector>();
    pendingHerbivores = new ArrayList<Creature>();
    pendingCarnivores = new ArrayList<Creature>();

    herbHistory = new int[GRAPH_HISTORY];
    carnHistory = new int[GRAPH_HISTORY];

    camera = new Camera(cameraWidthUnits, cameraHeightUnits,
                        gridSize, worldWidth, worldHeight);

    // Place the two lairs on opposite sides of the map
    lairCenters = new PVector[2];
    lairCenters[0] = findNearestLandPosition(worldWidth * 0.25, worldHeight * 0.35);
    lairCenters[1] = findNearestLandPosition(worldWidth * 0.72, worldHeight * 0.65);

    guardPosts = new PVector[2][];
    updateGuardPosts(0);
    updateGuardPosts(1);

    // Spawn initial creatures, split evenly between lairs
    for (int i = 0; i < herbivoreCount; i++) {
      herbivores.add(new Creature(randomLandPosition(), worldSize, false, -1));
    }
    for (int i = 0; i < carnivoreCount; i++) {
      int lair = i % 2;
      carnivores.add(new Creature(lairCenters[lair].copy(), worldSize, true, lair));
    }
    for (int i = 0; i < plantCount; i++) {
      plants.add(randomPlantPosition());
    }
  }

  // ── Terrain generation ────────────────────────────────────────
  void generateTerrain() {
    float scale   = 0.035;
    float offsetX = random(1000);
    float offsetY = random(1000);
    for (int x = 0; x < worldWidth; x++) {
      for (int y = 0; y < worldHeight; y++) {
        float n = noise((x + offsetX) * scale, (y + offsetY) * scale);
        if      (n < 0.30) terrain[x][y] = WATER;
        else if (n < 0.55) terrain[x][y] = GRASSLAND;
        else if (n < 0.75) terrain[x][y] = BRUSH;
        else               terrain[x][y] = ROCK;
      }
    }
  }

  void drawTerrain() {
    noStroke();
    int startX = camera.x,               startY = camera.y;
    int endX   = min(camera.x + camera.cols, worldWidth);
    int endY   = min(camera.y + camera.rows, worldHeight);
    for (int gx = startX; gx < endX; gx++) {
      for (int gy = startY; gy < endY; gy++) {
        switch (terrain[gx][gy]) {
          case GRASSLAND: fill(grassColor); break;
          case BRUSH:     fill(brushColor); break;
          case WATER:     fill(waterColor); break;
          case ROCK:      fill(rockColor);  break;
        }
        rect((gx - camera.x)*camera.cellSize,
             (gy - camera.y)*camera.cellSize,
             camera.cellSize, camera.cellSize);
      }
    }
  }

  int getTerrainAt(float wx, float wy) {
    int gx = constrain(int(wx), 0, worldWidth  - 1);
    int gy = constrain(int(wy), 0, worldHeight - 1);
    return terrain[gx][gy];
  }

  boolean isWalkable(float wx, float wy) {
    return getTerrainAt(wx, wy) != WATER;
  }

  // ── Main update / render loop ─────────────────────────────────
  void update() {
    if (!paused) {
      updateCreatures();
      updatePlantRegrowth();
      maybeEdgeSpawnHerbivores();
      flushPending();
      pruneCorpses();
      recordHistory();
    }

    drawTerrain();
    for (int i = 0; i < 2; i++) drawLair(i);
    camera.drawGrid();
    drawPlants();
    drawCreatures();
    drawHUD();
    drawSpawnIndicator();
    if (showGraph) drawGraph();
  }

  void updatePlantRegrowth() {
    regrowCounter++;
    if (regrowCounter >= regrowInterval && plants.size() < plantCap) {
      plants.add(randomPlantPosition());
      regrowCounter = 0;
    }
  }

  void updateCreatures() {
    for (Creature h : herbivores) h.update(this);
    for (Creature c : carnivores) c.update(this);
  }

  void flushPending() {
    for (Creature c : pendingHerbivores) herbivores.add(c);
    for (Creature c : pendingCarnivores) carnivores.add(c);
    pendingHerbivores.clear();
    pendingCarnivores.clear();
  }

  void pruneCorpses() {
    pruneList(herbivores, MAX_CORPSES);
    pruneList(carnivores, MAX_CORPSES);
  }

  void pruneList(ArrayList<Creature> list, int maxDead) {
    int dead = 0;
    for (int i = list.size() - 1; i >= 0; i--) {
      if (!list.get(i).lifecycle.alive) {
        dead++;
        if (dead > maxDead) list.remove(i);
      }
    }
  }

  void recordHistory() {
    herbHistory[historyHead] = countAlive(herbivores);
    carnHistory[historyHead] = countAlive(carnivores);
    historyHead = (historyHead + 1) % GRAPH_HISTORY;
  }

  // ── Herbivore edge spawning ───────────────────────────────────
  // Called every frame; spawns in batches every 120 frames when below threshold.
  int edgeSpawnCooldown = 0;
  void maybeEdgeSpawnHerbivores() {
    int alive = countAlive(herbivores);
    if (alive >= HERB_SPAWN_THRESHOLD) { edgeSpawnCooldown = 0; return; }
    edgeSpawnCooldown++;
    if (edgeSpawnCooldown < 120) return;  // throttle to once per 2 seconds
    edgeSpawnCooldown = 0;

    int deficit = HERB_SPAWN_THRESHOLD - alive;
    // Spawn 1 creature per 5 below threshold (min 1, max 6)
    int batch = constrain(deficit / 5, 1, 6);
    for (int i = 0; i < batch; i++) {
      if (countAlive(herbivores) >= MAX_HERBIVORES) break;
      PVector pos = randomEdgePosition();
      Creature h  = new Creature(pos, worldSize, false, -1);
      pendingHerbivores.add(h);
      herbEdgeSpawns++;
    }
  }

  // Random walkable position along the four map edges
  PVector randomEdgePosition() {
    PVector pos;
    int attempts = 0;
    do {
      int edge = int(random(4));
      float x, y;
      switch (edge) {
        case 0: x = random(worldWidth);   y = 1;                break;
        case 1: x = random(worldWidth);   y = worldHeight - 2;  break;
        case 2: x = 1;                    y = random(worldHeight); break;
        default:x = worldWidth - 2;       y = random(worldHeight); break;
      }
      pos = new PVector(x, y);
      attempts++;
    } while (!isWalkable(pos.x, pos.y) && attempts < 300);
    return pos;
  }

  // ── Reproduction ──────────────────────────────────────────────
  void spawnOffspring(Creature parentA, Creature parentB,
                      ArrayList<Creature> list) {
    if (!parentA.lifecycle.canReproduce() ||
        !parentB.lifecycle.canReproduce()) return;

    if (list == herbivores && countAlive(herbivores) >= MAX_HERBIVORES) return;
    if (list == carnivores && countAlive(carnivores) >= MAX_CARNIVORES) return;

    parentA.lifecycle.changeEnergy(-parentA.lifecycle.reproductionCost);
    parentB.lifecycle.changeEnergy(-parentB.lifecycle.reproductionCost);

    PVector childPos  = PVector.lerp(parentA.position, parentB.position, 0.5);
    LifecycleSystem childLife = crossbreed(parentA.lifecycle, parentB.lifecycle);

    // Child inherits parent A's lair allegiance (same species group)
    int childLair = parentA.lairIndex;
    Creature child = new Creature(childPos, worldSize,
                                  parentA.predator, childLair, childLife);

    if (list == herbivores) {
      pendingHerbivores.add(child);
      herbBirths++;
    } else {
      pendingCarnivores.add(child);
      carnBirths++;
    }

    parentA.state = "WANDER";
    parentB.state = "WANDER";
  }

  // ── Lair helpers ──────────────────────────────────────────────
  int lairOf(PVector pos) {
    // Returns which lair index this position is inside, or -1
    for (int i = 0; i < 2; i++) {
      if (PVector.dist(pos, lairCenters[i]) <= lairRadius) return i;
    }
    return -1;
  }

  boolean isInLair(PVector pos, int lairIdx) {
    return PVector.dist(pos, lairCenters[lairIdx]) <= lairRadius;
  }

  boolean isInRestArea(PVector pos, int lairIdx) {
    return PVector.dist(pos, lairCenters[lairIdx]) <= lairRestRadius;
  }

  // Distance between the two lair centers (used for enemy detection radius)
  float lairSeparation() {
    return PVector.dist(lairCenters[0], lairCenters[1]);
  }

  void updateGuardPosts(int idx) {
    guardPosts[idx] = new PVector[2];
    PVector c = lairCenters[idx];
    guardPosts[idx][0] = new PVector(
      constrain(c.x - lairRadius * 0.65, 1, worldWidth  - 1),
      constrain(c.y,                     1, worldHeight - 1));
    guardPosts[idx][1] = new PVector(
      constrain(c.x + lairRadius * 0.65, 1, worldWidth  - 1),
      constrain(c.y,                     1, worldHeight - 1));
  }

  // Guard-slot logic: first two alive carnivores of a given lair
  boolean isCarnivoreGuard(Creature candidate) {
    return candidate == getLairGuard(candidate.lairIndex, 0) ||
           candidate == getLairGuard(candidate.lairIndex, 1);
  }

  Creature getLairGuard(int lairIdx, int slot) {
    int found = 0;
    for (Creature c : carnivores) {
      if (!c.lifecycle.alive) continue;
      if (c.lairIndex != lairIdx) continue;
      if (found == slot) return c;
      found++;
    }
    return null;
  }

  PVector getCarnivoreGuardPost(Creature guard) {
    int li = guard.lairIndex;
    if (guard == getLairGuard(li, 0)) return guardPosts[li][0].copy();
    return guardPosts[li][1].copy();
  }

  int countLairResidents(int lairIdx) {
    int n = 0;
    for (Creature c : carnivores) {
      if (!c.lifecycle.alive)         continue;
      if (c.lairIndex != lairIdx)     continue;
      if (isCarnivoreGuard(c))        continue;
      if (!isInLair(c.position, lairIdx)) continue;
      n++;
    }
    return n;
  }

  boolean isLairOverCapacity(int lairIdx) {
    return countLairResidents(lairIdx) > maxLairResidents;
  }

  // Strongest non-guard resident inside a specific lair
  Creature findStrongestLairResident(int lairIdx) {
    Creature best = null;
    for (Creature c : carnivores) {
      if (!c.lifecycle.alive)             continue;
      if (c.lairIndex != lairIdx)         continue;
      if (isCarnivoreGuard(c))            continue;
      if (!isInLair(c.position, lairIdx)) continue;
      if (best == null || c.lifecycle.energy > best.lifecycle.energy) best = c;
    }
    return best;
  }

  boolean shouldLeaveOvercrowdedLair(Creature candidate) {
    if (candidate == null || !candidate.lifecycle.alive) return false;
    if (isCarnivoreGuard(candidate))                     return false;
    int li = candidate.lairIndex;
    if (!isInLair(candidate.position, li))               return false;

    ArrayList<Creature> residents = new ArrayList<Creature>();
    for (Creature c : carnivores) {
      if (!c.lifecycle.alive)         continue;
      if (c.lairIndex != li)          continue;
      if (isCarnivoreGuard(c))        continue;
      if (!isInLair(c.position, li))  continue;
      residents.add(c);
    }

    while (residents.size() > maxLairResidents) {
      Creature strongest = residents.get(0);
      for (Creature c : residents)
        if (c.lifecycle.energy > strongest.lifecycle.energy) strongest = c;
      if (strongest == candidate) return true;
      residents.remove(strongest);
    }
    return false;
  }

  // Nearest herbivore INSIDE a specific lair (for guards to chase)
  Creature findNearestHerbivoreInLair(PVector from, float range, int lairIdx) {
    Creature best = null;
    float bestDist = range;
    for (Creature h : herbivores) {
      if (!h.lifecycle.alive)             continue;
      if (!isInLair(h.position, lairIdx)) continue;
      float d = PVector.dist(from, h.position);
      if (d < bestDist) { bestDist = d; best = h; }
    }
    return best;
  }

  // Nearest ENEMY carnivore within range (different lair allegiance)
  Creature findNearestEnemyCarnivore(PVector from, float range, int myLairIndex) {
    Creature best = null;
    float bestDist = range;
    for (Creature c : carnivores) {
      if (!c.lifecycle.alive)      continue;
      if (c.lairIndex == myLairIndex) continue;  // same allegiance, skip
      float d = PVector.dist(from, c.position);
      if (d < bestDist) { bestDist = d; best = c; }
    }
    return best;
  }

  // ── Spatial queries (unchanged) ───────────────────────────────
  PVector findNearestPlant(PVector from, float range) {
    PVector best = null;
    float bestDist = range;
    for (PVector plant : plants) {
      float d = PVector.dist(from, plant);
      if (d < bestDist) { bestDist = d; best = plant; }
    }
    return best;
  }

  PVector findNearestPlantOutsideLairs(PVector from, float range) {
    PVector best = null;
    float bestDist = range;
    for (PVector plant : plants) {
      if (lairOf(plant) >= 0) continue;  // skip plants inside any lair
      float d = PVector.dist(from, plant);
      if (d < bestDist) { bestDist = d; best = plant; }
    }
    return best;
  }

  Creature findNearestCreature(PVector from, ArrayList<Creature> list,
                                float range) {
    Creature best = null;
    float bestDist = range;
    for (Creature c : list) {
      if (!c.lifecycle.alive) continue;
      float d = PVector.dist(from, c.position);
      if (d < bestDist) { bestDist = d; best = c; }
    }
    return best;
  }

  ArrayList<Creature> findNearbyCarnivores(PVector pos, float range,
                                            Creature self) {
    ArrayList<Creature> nearby = new ArrayList<Creature>();
    for (Creature c : carnivores) {
      if (c == self || !c.lifecycle.alive) continue;
      if (PVector.dist(pos, c.position) <= range) nearby.add(c);
    }
    return nearby;
  }

  Creature findNearestReadyMate(PVector from, ArrayList<Creature> list,
                                 Creature self, float range) {
    Creature best = null;
    float bestDist = range;
    for (Creature c : list) {
      if (c == self)              continue;
      if (!c.lifecycle.alive)     continue;
      if (!c.lifecycle.canReproduce()) continue;
      // Carnivores must share lair allegiance to mate
      if (self.predator && c.lairIndex != self.lairIndex) continue;
      float d = PVector.dist(from, c.position);
      if (d < bestDist) { bestDist = d; best = c; }
    }
    return best;
  }

  void consumePlant(PVector plant) {
    if (plant == null) return;
    plant.set(randomPlantPosition());
  }

  // ── Roam radius for a given carnivore ─────────────────────────
  // At high energy → small radius (stay near lair).
  // At low energy  → large radius (hunt far afield).
  float roamRadiusFor(Creature c) {
    float t = c.lifecycle.energy / c.lifecycle.maxEnergy;  // 1 = full, 0 = starving
    // Linearly interpolate: full energy → MIN radius, zero energy → MAX radius
    return lerp(ROAM_RADIUS_MAX, ROAM_RADIUS_MIN, t);
  }

  // Is a position within the carnivore's allowed roam circle?
  boolean isInRoamRadius(PVector pos, int lairIdx, float radius) {
    return PVector.dist(pos, lairCenters[lairIdx]) <= radius;
  }

  // A random wander target within roam radius that is walkable
  PVector randomRoamTarget(int lairIdx, float radius) {
    PVector center = lairCenters[lairIdx];
    PVector target;
    int attempts = 0;
    do {
      float angle = random(TWO_PI);
      float dist  = random(radius * 0.4, radius);
      target = new PVector(center.x + cos(angle) * dist,
                           center.y + sin(angle) * dist);
      target.x = constrain(target.x, 1, worldWidth  - 1);
      target.y = constrain(target.y, 1, worldHeight - 1);
      attempts++;
    } while (!isWalkable(target.x, target.y) && attempts < 200);
    return target;
  }

  // ── Drawing ───────────────────────────────────────────────────
  void drawPlants() {
    noStroke();
    fill(70, 150, 70);
    for (PVector plant : plants) {
      if (!camera.isVisible(plant)) continue;
      PVector sp = camera.worldToScreen(plant);
      ellipse(sp.x, sp.y, 8, 8);
    }
  }

  void drawLair(int idx) {
    PVector c = lairCenters[idx];
    if (!camera.isVisible(c)) return;
    PVector sc   = camera.worldToScreen(c);
    float ld = lairRadius     * 2 * camera.cellSize;
    float rd = lairRestRadius * 2 * camera.cellSize;

    color baseCol = lairHudColor[idx];
    noStroke();
    fill(red(baseCol), green(baseCol), blue(baseCol), 60);
    ellipse(sc.x, sc.y, ld, ld);
    fill(red(baseCol), green(baseCol), blue(baseCol), 90);
    ellipse(sc.x, sc.y, rd, rd);

    stroke(red(baseCol), green(baseCol), blue(baseCol), 180);
    noFill();
    ellipse(sc.x, sc.y, ld, ld);
    noStroke();

    fill(255, 230, 220);
    textSize(12);
    String label = (idx == 0) ? "Lair 1" : "Lair 2";
    text(label, sc.x - 22, sc.y - ld * 0.5 - 4);
  }

  void drawCreatures() {
    for (Creature h : herbivores) h.draw(camera, showRanges, this);
    for (Creature c : carnivores) c.draw(camera, showRanges, this);
  }

  // ── HUD ───────────────────────────────────────────────────────
  void drawHUD() {
    int aH = countAlive(herbivores);
    int aC = countAlive(carnivores);

    fill(0, 170);
    noStroke();
    rect(10, 10, 370, 240, 6);

    fill(255);
    textSize(18);
    text("EcoSim", 20, 32);
    textSize(12);
    fill(200);
    text("Arrows: camera  R: ranges  P: pause  G: graph  A/D: spawn type  Space: spawn", 20, 48);

    fill(255);
    textSize(13);
    text("Herbivores alive : " + aH +
         "  (births: " + herbBirths +
         "  edge: " + herbEdgeSpawns + ")", 20, 68);
    text("Carnivores alive : " + aC +
         "  (births: " + carnBirths + ")", 20, 84);
    text("Plants           : " + plants.size(), 20, 100);

    // Per-lair counts
    int c0 = countAliveLair(0), c1 = countAliveLair(1);
    fill(lairHudColor[0]); text("Lair 1: " + c0, 20, 118);
    fill(lairHudColor[1]); text("Lair 2: " + c1, 20, 134);

    fill(255);
    text("Herbivore avg: " + avgStatsLabel(herbivores), 20, 152);
    text("Carnivore avg: " + avgStatsLabel(carnivores), 20, 168);
    text("Camera: (" + camera.x + ", " + camera.y + ")", 20, 184);
    text("Repro threshold: 75  |  Cost: 25 / parent", 20, 200);
    text("Herb edge-spawn threshold: " + HERB_SPAWN_THRESHOLD, 20, 216);
    text("Hibernate: return >" + int(HIBERNATE_RETURN_THRESHOLD*100) +
         "% energy, exit <" + int(HIBERNATE_EXIT_THRESHOLD*100) + "%", 20, 232);
  }

  // ── Spawn type indicator (bottom-left) ────────────────────────
  void drawSpawnIndicator() {
    int bx = 10, by = height - 144;
    fill(0, 160);
    noStroke();
    rect(bx, by, 160, 34, 5);
    fill(255);
    textSize(11);
    text("Spawn [A/D + Space]:", bx + 6, by + 14);
    color c;
    switch (spawnType) {
      case 0:  c = color( 80, 140, 255); break;
      case 1:  c = color(230,  80,  80); break;
      default: c = color( 170, 170, 170); break;
    }
    fill(c);
    textSize(13);
    text("▶ " + spawnTypeNames[spawnType], bx + 6, by + 29);
  }

  // ── Population graph ──────────────────────────────────────────
  void drawGraph() {
    int gx = width - GRAPH_HISTORY - 15;
    int gy = height - 80;
    int gh = 60;

    fill(0, 160);
    noStroke();
    rect(gx - 5, gy - gh - 15, GRAPH_HISTORY + 10, gh + 30, 4);
    fill(180);
    textSize(10);
    text("Population (last " + GRAPH_HISTORY + " frames)", gx, gy - gh - 2);

    int peak = 10;
    for (int i = 0; i < GRAPH_HISTORY; i++)
      peak = max(peak, herbHistory[i], carnHistory[i]);

    for (int i = 1; i < GRAPH_HISTORY; i++) {
      int prev = (historyHead + i - 1) % GRAPH_HISTORY;
      int curr = (historyHead + i)     % GRAPH_HISTORY;
      float x0 = gx + i - 1, x1 = gx + i;
      stroke(80, 140, 255, 200);
      line(x0, gy - gh * herbHistory[prev] / (float)peak,
           x1, gy - gh * herbHistory[curr] / (float)peak);
      stroke(220, 80, 80, 200);
      line(x0, gy - gh * carnHistory[prev] / (float)peak,
           x1, gy - gh * carnHistory[curr] / (float)peak);
    }
    noStroke();
    fill( 80, 140, 255); rect(gx,      gy + 5, 10, 8);
    fill(200); text("Herb", gx + 14,   gy + 13);
    fill(220,  80,  80); rect(gx + 50, gy + 5, 10, 8);
    fill(200); text("Carn", gx + 64,   gy + 13);
  }

  // ── Controls ──────────────────────────────────────────────────
  void handleKeyPressed(char pressedKey, int pressedKeyCode) {
    handleKey(pressedKey, pressedKeyCode);
  }

  void handleKey(char pressedKey, int pressedKeyCode) {
    if (pressedKeyCode == LEFT)  camera.move(-4,  0);
    if (pressedKeyCode == RIGHT) camera.move( 4,  0);
    if (pressedKeyCode == UP)    camera.move( 0, -4);
    if (pressedKeyCode == DOWN)  camera.move( 0,  4);
    if (pressedKey == 'r' || pressedKey == 'R') showRanges = !showRanges;
    if (pressedKey == 'p' || pressedKey == 'P') paused     = !paused;
    if (pressedKey == 'g' || pressedKey == 'G') showGraph  = !showGraph;

    // Cycle spawn type
    if (pressedKey == 'a' || pressedKey == 'A' || pressedKey == 'd' || pressedKey == 'D')
      spawnType = (spawnType + 1) % 2;

    // Spawn at mouse world position
    if (pressedKey == ' ') {
      // Convert mouse screen coords → world coords
      float wx = camera.x + mouseX / (float)camera.cellSize;
      float wy = camera.y + mouseY / (float)camera.cellSize;
      if (isWalkable(wx, wy)) {
        PVector pos = new PVector(wx, wy);
        switch (spawnType) {
          case 0:
            if (countAlive(herbivores) < MAX_HERBIVORES)
              herbivores.add(new Creature(pos, worldSize, false, -1));
            break;
          case 1:
            if (countAlive(carnivores) < MAX_CARNIVORES) {
              // Assign to whichever lair is closer
              int li = (PVector.dist(pos, lairCenters[0]) <
                        PVector.dist(pos, lairCenters[1])) ? 0 : 1;
              carnivores.add(new Creature(pos, worldSize, true, li));
            }
            break;
        }
      }
    }
  }

  // ── Utility ───────────────────────────────────────────────────
  int countAlive(ArrayList<Creature> creatures) {
    int n = 0;
    for (Creature c : creatures) if (c.lifecycle.alive) n++;
    return n;
  }

  int countAliveLair(int lairIdx) {
    int n = 0;
    for (Creature c : carnivores)
      if (c.lifecycle.alive && c.lairIndex == lairIdx) n++;
    return n;
  }

  String avgStatsLabel(ArrayList<Creature> list) {
    int n = 0;
    float sumSpd = 0, sumMet = 0, sumDet = 0;
    for (Creature c : list) {
      if (!c.lifecycle.alive) continue;
      sumSpd += c.lifecycle.maxSpeed;
      sumMet += c.lifecycle.metabolism;
      sumDet += c.lifecycle.detectionRange;
      n++;
    }
    if (n == 0) return "(none alive)";
    return String.format("spd:%.3f  met:%.3f  det:%.1f", sumSpd/n, sumMet/n, sumDet/n);
  }

  PVector randomLandPosition() {
    PVector pos;
    int attempts = 0;
    do {
      pos = new PVector(random(worldWidth), random(worldHeight));
      attempts++;
    } while (!isWalkable(pos.x, pos.y) && attempts < 500);
    return pos;
  }

  PVector randomPlantPosition() {
    PVector pos;
    int attempts = 0;
    do {
      pos = new PVector(random(50, worldWidth-50), random(50, worldHeight-50));
      attempts++;
    } while ((!isGoodPlantTile(pos.x, pos.y) || lairOf(pos) >= 0) &&
             attempts < 500);
    return pos;
  }

  boolean isGoodPlantTile(float wx, float wy) {
    int t = getTerrainAt(wx, wy);
    if (t != GRASSLAND && t != BRUSH) return false;
    int gx = int(wx), gy = int(wy);
    for (int dx = -2; dx <= 2; dx++)
      for (int dy = -2; dy <= 2; dy++) {
        int nx = gx+dx, ny = gy+dy;
        if (nx >= 0 && nx < worldWidth && ny >= 0 && ny < worldHeight)
          if (terrain[nx][ny] == WATER) return false;
      }
    return true;
  }

  // Exit point from a specific lair
  PVector getLairExitPoint(PVector from, int lairIdx) {
    PVector lc  = lairCenters[lairIdx];
    PVector dir = PVector.sub(from, lc);
    if (dir.magSq() < 0.001) dir = PVector.random2D();
    dir.normalize();
    PVector target = PVector.add(lc, PVector.mult(dir, lairRadius + 8));
    return findNearestLandPosition(target.x, target.y);
  }

  PVector findNearestLandPosition(float preferredX, float preferredY) {
    int baseX = constrain(round(preferredX), 0, worldWidth  - 1);
    int baseY = constrain(round(preferredY), 0, worldHeight - 1);
    for (int radius = 0; radius < max(worldWidth, worldHeight); radius++)
      for (int dx = -radius; dx <= radius; dx++)
        for (int dy = -radius; dy <= radius; dy++) {
          int x = constrain(baseX+dx, 0, worldWidth -1);
          int y = constrain(baseY+dy, 0, worldHeight-1);
          if (isWalkable(x, y)) return new PVector(x, y);
        }
    return randomLandPosition();
  }
}
