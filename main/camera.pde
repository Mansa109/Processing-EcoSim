// ============================================================
//  EcoSim – camera.pde
//  Viewport movement, visibility checks, world→screen coords.
// ============================================================

class Camera {
  int x;
  int y;
  int cols;
  int rows;
  int cellSize;
  int worldCols;
  int worldRows;

  Camera(int visibleCols, int visibleRows, int cellSizePixels,
         int maxWorldCols, int maxWorldRows) {
    cols      = visibleCols;
    rows      = visibleRows;
    cellSize  = cellSizePixels;
    worldCols = maxWorldCols;
    worldRows = maxWorldRows;
    x = 0;
    y = 0;
  }

  void move(int dx, int dy) {
    x = constrain(x + dx, 0, max(0, worldCols - cols));
    y = constrain(y + dy, 0, max(0, worldRows - rows));
  }

  boolean isVisible(PVector worldPosition) {
    return worldPosition.x >= x
      && worldPosition.x < x + cols
      && worldPosition.y >= y
      && worldPosition.y < y + rows;
  }

  PVector worldToScreen(PVector worldPosition) {
    return new PVector(
      (worldPosition.x - x) * cellSize,
      (worldPosition.y - y) * cellSize
    );
  }

  void drawGrid() {
    stroke(120, 110, 95, 80);
    for (int gx = 0; gx <= cols; gx++) {
      line(gx * cellSize, 0, gx * cellSize, rows * cellSize);
    }
    for (int gy = 0; gy <= rows; gy++) {
      line(0, gy * cellSize, cols * cellSize, gy * cellSize);
    }
  }
}
