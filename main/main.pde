// ============================================================
//  EcoSim – main.pde
//  Entry point: setup / draw / key forwarding
// ============================================================

World w;

void setup() {
  size(800, 800);
  textSize(12);
  int worldWidth = 200;
  int worldHeight = 200;
  int gridSize = 8;
  int initHerbivore = 60;
  int initCarnivore = 30;
  int initPlant = 120;
  int cameraWidth = 100;
  int cameraHeight = 100;

  w = new World(worldWidth, worldHeight, gridSize, initHerbivore, initCarnivore, initPlant, cameraWidth, cameraHeight);
}

void draw() {
  background(214, 190, 140);
  w.update();
}

void keyPressed() {
  w.handleKeyPressed(key, keyCode);
}
