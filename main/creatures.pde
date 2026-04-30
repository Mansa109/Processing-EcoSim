// ============================================================
//  EcoSim – creatures.pde
//  Creature: movement, steering, state machine, drawing.
// ============================================================

class Creature {
  // Lair re-entry constants kept for GUARD minimum-stay logic
  static final int LAIR_MIN_STAY_FRAMES = 5 * 60;

  PVector position;
  PVector velocity;
  PVector acceleration;
  PVector boundaries;

  float energyValue;
  float wanderAngle;
  float boundaryTurn;
  float panicAngle;

  boolean predator;
  int     lairIndex;   // -1 = no lair (herbivore), 0 or 1 = allegiance
  String  state;

  // Roam target (refreshed when the old one is reached)
  PVector roamTarget;

  int enteredLairAtFrame;

  LifecycleSystem lifecycle;

  // ── Standard spawn constructor ────────────────────────────────
  Creature(PVector pos, PVector worldSize, boolean isPredator, int lairIdx) {
    position    = pos.copy();
    boundaries  = worldSize.copy();
    predator    = isPredator;
    lairIndex   = lairIdx;

    lifecycle   = new LifecycleSystem(int(random(65, 95)), isPredator);

    velocity    = PVector.random2D();
    velocity.mult(random(lifecycle.maxSpeed * 0.35, lifecycle.maxSpeed));
    acceleration = new PVector();

    energyValue       = predator ? 20 : 35;
    wanderAngle       = random(TWO_PI);
    boundaryTurn      = random(TWO_PI / 4);
    panicAngle        = random(TWO_PI / 8);
    state             = "WANDER";
    roamTarget        = null;
    enteredLairAtFrame = -LAIR_MIN_STAY_FRAMES;
  }

  // ── Child constructor (crossbred LifecycleSystem) ─────────────
  Creature(PVector pos, PVector worldSize, boolean isPredator,
           int lairIdx, LifecycleSystem inheritedLifecycle) {
    position    = pos.copy();
    boundaries  = worldSize.copy();
    predator    = isPredator;
    lairIndex   = lairIdx;
    lifecycle   = inheritedLifecycle;

    velocity    = PVector.random2D();
    velocity.mult(lifecycle.maxSpeed * 0.5);
    acceleration = new PVector();

    energyValue       = predator ? 35 : 20;
    wanderAngle       = random(TWO_PI);
    boundaryTurn      = random(TWO_PI / 4);
    panicAngle        = random(TWO_PI / 8);
    state             = "WANDER";
    roamTarget        = null;
    enteredLairAtFrame = -LAIR_MIN_STAY_FRAMES;
  }

  // ── Main update ───────────────────────────────────────────────
  void update(World world) {
    if (!lifecycle.alive) {
      state = "DEAD";
      velocity.set(0, 0);
      acceleration.set(0, 0);
      return;
    }

    if (predator) {
      updateCarnivore(world);
    } else {
      updateHerbivore(world);
    }

    avoidWater(world);

    velocity.add(acceleration);
    velocity.limit(lifecycle.maxSpeed);
    position.add(velocity);
    acceleration.mult(0);

    keepInBounds();

    // Safety: snap off water
    if (!world.isWalkable(position.x, position.y)) {
      position.sub(velocity);
      velocity.mult(-0.5);
      wanderAngle += PI * 0.5;
      position.x = constrain(position.x, 1, boundaries.x - 1);
      position.y = constrain(position.y, 1, boundaries.y - 1);
    }

    // Guards are pinned to their posts
    if (predator && world.isCarnivoreGuard(this)) {
      position.set(world.getCarnivoreGuardPost(this));
      velocity.set(0, 0);
      acceleration.set(0, 0);
    }

    // Track time entered lair
    if (predator && !world.isCarnivoreGuard(this) &&
        world.isInLair(position, lairIndex)) {
      if (enteredLairAtFrame < 0 ||
          !world.isInLair(PVector.sub(position, velocity), lairIndex)) {
        enteredLairAtFrame = frameCount;
      }
    }

    // Metabolism (guards burn nothing)
    if (predator && world.isCarnivoreGuard(this)) {
      lifecycle.energy = lifecycle.maxEnergy;
      lifecycle.hunger = 0;
    } else if (state.equals("HIBERNATE")) {
      // Hibernate: burn at 30 % of normal rate
      lifecycle.changeEnergy(-lifecycle.metabolism * 0.30);
      lifecycle.hunger = 1 - (lifecycle.energy / lifecycle.maxEnergy);
    } else {
      lifecycle.changeEnergy(-lifecycle.metabolism);
      lifecycle.hunger = 1 - (lifecycle.energy / lifecycle.maxEnergy);
    }

    if (lifecycle.energy <= 0) {
      lifecycle.die();
      state = "DEAD";
      velocity.set(0, 0);
    }
  }

  // ── Carnivore behaviour ───────────────────────────────────────
  void updateCarnivore(World world) {
    boolean insideLair   = world.isInLair(position, lairIndex);
    boolean highEnergy   = lifecycle.energy >= lifecycle.maxEnergy * HIBERNATE_RETURN_THRESHOLD;
    boolean lowEnergy    = lifecycle.energy <  lifecycle.maxEnergy * HIBERNATE_EXIT_THRESHOLD;
    float   roamR        = world.roamRadiusFor(this);

    // ── Guards ──
    if (world.isCarnivoreGuard(this)) {
      lifecycle.energy = lifecycle.maxEnergy;
      state = "GUARD";
      PVector post = world.getCarnivoreGuardPost(this);
      seek(post);
      if (isCloseTo(post, 1.4)) velocity.mult(0.45);

      // Guards hunt enemy carnivores that stray near the lair
      Creature enemy = world.findNearestEnemyCarnivore(
        position, world.lairRadius * 1.5, lairIndex);
      if (enemy != null) {
        state = "HUNT_ENEMY";
        seek(enemy.position);
        if (isCloseTo(enemy.position, 1.2)) {
          enemy.lifecycle.die();
          enemy.state = "DEAD";
          lifecycle.changeEnergy(enemy.energyValue);
        }
        return;
      }

      // Guards also cull herbivore intruders
      Creature intruder = world.findNearestHerbivoreInLair(
        position, lifecycle.detectionRange * 1.35, lairIndex);
      if (intruder != null) {
        state = "DEFEND";
        seek(intruder.position);
        if (isCloseTo(intruder.position, 1.2)) {
          intruder.lifecycle.die();
          intruder.state = "DEAD";
          lifecycle.changeEnergy(energyValue);
        }
        return;
      }

      // Evict overcrowded residents
      Creature strongest = world.findStrongestLairResident(lairIndex);
      if (world.isLairOverCapacity(lairIndex) && strongest != null &&
          world.shouldLeaveOvercrowdedLair(strongest) &&
          strongest.lifecycle.energy >= strongest.lifecycle.maxEnergy * 0.60 &&
          frameCount - strongest.enteredLairAtFrame >= LAIR_MIN_STAY_FRAMES) {
        strongest.beginLairExit(world);
      }
      return;
    }

    // ── Non-guard carnivore ──

    // Hunt enemy carnivores near OWN lair (any resident/roaming defender)
    Creature enemy = world.findNearestEnemyCarnivore(
      position, world.lairRadius * 1.2, lairIndex);
    if (enemy != null) {
      state = "HUNT_ENEMY";
      seek(enemy.position);
      if (isCloseTo(enemy.position, 1.2)) {
        enemy.lifecycle.die();
        enemy.state = "DEAD";
        lifecycle.changeEnergy(enemy.energyValue);
      }
      return;
    }

    // Defend lair from herbivore intruders when inside
    if (insideLair) {
      Creature intruder = world.findNearestHerbivoreInLair(
        position, lifecycle.detectionRange, lairIndex);
      if (intruder != null) {
        state = "DEFEND";
        seek(intruder.position);
        if (isCloseTo(intruder.position, 1.2)) {
          intruder.lifecycle.die();
          intruder.state = "DEAD";
          lifecycle.changeEnergy(energyValue);
        }
        return;
      }
    }

    // Return to lair when very well-fed
    if (highEnergy && !insideLair) {
      state = "RETURN";
      seek(world.lairCenters[lairIndex]);
      return;
    }

    // Hibernate inside lair until low energy
    if (insideLair && !lowEnergy) {
      // Evict if overcrowded
      if (world.shouldLeaveOvercrowdedLair(this) &&
          lifecycle.energy >= lifecycle.maxEnergy * 0.60 &&
          frameCount - enteredLairAtFrame >= LAIR_MIN_STAY_FRAMES) {
        beginLairExit(world);
        return;
      }
      state = "HIBERNATE";
      velocity.mult(0.15);  // nearly stationary
      return;
    }

    // Reproduce (outside lair only, while energy permits)
    if (lifecycle.canReproduce() && !insideLair) {
      Creature mate = world.findNearestReadyMate(
        position, world.carnivores, this, lifecycle.detectionRange);
      if (mate != null) {
        state = "REPRODUCE";
        seek(mate.position);
        if (isCloseTo(mate.position, lifecycle.mateRange)) {
          world.spawnOffspring(this, mate, world.carnivores);
        }
        return;
      }
    }

    // Roam within energy-scaled radius – chase prey if found
    Creature prey = world.findNearestCreature(
      position, world.herbivores,
      world.lairRadius + lifecycle.detectionRange * (1 + lifecycle.hunger));

    if (prey != null && lifecycle.hunger > 0.25) {
      // Only chase prey if it is within roam radius or we are very hungry
      boolean preyInRange = world.isInRoamRadius(prey.position, lairIndex, roamR);
      if (preyInRange || lifecycle.hunger > 0.70) {
        state = "CHASE";
        seek(prey.position);
        if (isCloseTo(prey.position, 1.2)) {
          prey.lifecycle.die();
          prey.state = "DEAD";
          lifecycle.changeEnergy(prey.energyValue);
        }
        return;
      }
    }

    // Roam patrol within radius
    state = "ROAM";
    if (roamTarget == null || isCloseTo(roamTarget, 1.5) ||
        !world.isInRoamRadius(roamTarget, lairIndex, roamR)) {
      roamTarget = world.randomRoamTarget(lairIndex, roamR);
    }
    seek(roamTarget);
  }

  // ── Herbivore behaviour ───────────────────────────────────────
  void updateHerbivore(World world) {
    Creature nearestPredator = world.findNearestCreature(
      position, world.carnivores, lifecycle.detectionRange);
    PVector nearestPlant = world.findNearestPlantOutsideLairs(
      position, lifecycle.detectionRange * (1 + lifecycle.hunger));

    // Avoid all lairs
    for (int i = 0; i < 2; i++) {
      if (PVector.dist(position, world.lairCenters[i]) <=
          world.lairRadius - 2.5) {
        state = "AVOID_LAIR";
        flee(world.lairCenters[i]);
        return;
      }
    }

    // Flee predators
    if (nearestPredator != null &&
        ((nearestPlant != null &&
          PVector.dist(position, nearestPredator.position) <
          PVector.dist(position, nearestPlant) + 5) ||
         nearestPlant == null)) {
      state = "FLEE";
      flee(nearestPredator.position);
      return;
    }

    // Reproduce
    if (lifecycle.canReproduce()) {
      Creature mate = world.findNearestReadyMate(
        position, world.herbivores, this, lifecycle.detectionRange);
      if (mate != null) {
        state = "REPRODUCE";
        seek(mate.position);
        if (isCloseTo(mate.position, lifecycle.mateRange)) {
          world.spawnOffspring(this, mate, world.herbivores);
        }
        return;
      }
    }

    // Seek food
    if (nearestPlant != null && lifecycle.hunger > 0.25) {
      state = "SEEK";
      seek(nearestPlant);
      if (isCloseTo(nearestPlant, 1.0)) {
        world.consumePlant(nearestPlant);
        lifecycle.changeEnergy(energyValue);
      }
      return;
    }

    state = "WANDER";
    wander();
  }

  // ── Drawing ───────────────────────────────────────────────────
  void draw(Camera camera, boolean showRanges, World world) {
    if (!camera.isVisible(position)) return;

    PVector screenPos = camera.worldToScreen(position);
    float   heading   = velocity.magSq() > 0.0001 ? velocity.heading() : 0;

    pushMatrix();
    translate(screenPos.x, screenPos.y);
    rotate(heading);

    if (showRanges && lifecycle.alive) {
      noFill();
      stroke(255, 100);
      float r = lifecycle.detectionRange * camera.cellSize;
      ellipse(0, 0, r * 2, r * 2);
      if (lifecycle.canReproduce()) {
        stroke(255, 150, 200, 160);
        float mr = lifecycle.mateRange * camera.cellSize;
        ellipse(0, 0, mr * 2, mr * 2);
      }
    }

    noStroke();

    if (!lifecycle.alive) {
      fill(predator ? color(70, 40, 40) : color(45, 60, 90));
      triangle(8, 0, -7, -5, -7, 5);
    } else {
      float t = lifecycle.energy / lifecycle.maxEnergy;
      if (predator) {
        // Tint by allegiance
        color lo = (lairIndex == 0) ? world.lairColorLow[0]  : world.lairColorLow[1];
        color hi = (lairIndex == 0) ? world.lairColorHigh[0] : world.lairColorHigh[1];
        if (state.equals("GUARD")) {
          // Guards are bright white-ish
          fill(lerpColor(color(160), color(255), t));
        } else {
          fill(lerpColor(lo, hi, t));
        }
      } else {
        fill(lerpColor(color(30, 50, 120), color(80, 140, 255), t));
      }
      triangle(10, 0, -8, -6, -8, 6);

      // Heart icon while reproducing
      if (state.equals("REPRODUCE")) {
        popMatrix();
        pushMatrix();
        translate(screenPos.x, screenPos.y);
        fill(255, 100, 160);
        noStroke();
        textSize(11);
        text("♥", -4, -10);
        popMatrix();
        pushMatrix();
        translate(screenPos.x, screenPos.y);
        rotate(heading);
      }

      // "Z" icon while hibernating
      if (state.equals("HIBERNATE")) {
        popMatrix();
        pushMatrix();
        translate(screenPos.x, screenPos.y);
        fill(200, 220, 255);
        noStroke();
        textSize(11);
        text("Z", -3, -10);
        popMatrix();
        pushMatrix();
        translate(screenPos.x, screenPos.y);
        rotate(heading);
      }
    }

    popMatrix();

    // State label and energy bar (live creatures only)
    if (lifecycle.alive) {
      fill(0);
      textSize(10);
      text(state, screenPos.x + 8, screenPos.y - 8);

      float barW  = 14;
      float fill_ = barW * (lifecycle.energy / lifecycle.maxEnergy);
      noStroke();
      fill(60);
      rect(screenPos.x - 7, screenPos.y + 8, barW, 3);
      fill(predator ? color(220, 80, 80) : color(80, 160, 255));
      rect(screenPos.x - 7, screenPos.y + 8, fill_, 3);
    }
  }

  // ── Steering helpers ──────────────────────────────────────────
  void applyForce(PVector force) { acceleration.add(force); }

  void beginLairExit(World world) {
    state = "LEAVE_LAIR";
    seek(world.getLairExitPoint(position, lairIndex));
  }

  void seek(PVector target) {
    PVector desired = PVector.sub(target, position);
    if (desired.magSq() == 0) return;
    desired.normalize();
    desired.mult(lifecycle.maxSpeed);
    PVector steer = PVector.sub(desired, velocity);
    steer.limit(lifecycle.maxForce);
    applyForce(steer);
  }

  void flee(PVector threat) {
    PVector desired = PVector.sub(position, threat);
    if (desired.magSq() == 0) return;
    desired.normalize();
    desired.rotate(panicAngle);
    desired.mult(lifecycle.maxSpeed);
    PVector steer = PVector.sub(desired, velocity);
    steer.limit(lifecycle.maxForce * 1.3);
    applyForce(steer);
  }

  void wander() {
    wanderAngle += random(-0.35, 0.35);
    PVector circleCenter = velocity.copy();
    if (circleCenter.magSq() == 0) circleCenter = PVector.random2D();
    circleCenter.normalize();
    circleCenter.mult(2.0);
    PVector displacement = new PVector(cos(wanderAngle), sin(wanderAngle));
    displacement.mult(1.2);
    PVector wanderForce = PVector.add(circleCenter, displacement);
    wanderForce.limit(lifecycle.maxForce);
    applyForce(wanderForce);
  }

  void keepInBounds() {
    float ef = 0.045;
    if (position.x < 3)                applyForce(new PVector( ef, 0));
    if (position.x > boundaries.x - 3) applyForce(new PVector(-ef, 0));
    if (position.y < 3)                applyForce(new PVector(0,  ef));
    if (position.y > boundaries.y - 3) applyForce(new PVector(0, -ef));
    if (position.x < 3 || position.x > boundaries.x - 3) velocity.rotate(boundaryTurn);
    if (position.y < 3 || position.y > boundaries.y - 3) velocity.rotate(boundaryTurn);
    position.x = constrain(position.x, 1, boundaries.x - 1);
    position.y = constrain(position.y, 1, boundaries.y - 1);
  }

  boolean isCloseTo(PVector target, float radius) {
    return PVector.dist(position, target) <= radius;
  }

  // MAP (Rikesh): Water avoidance
  void avoidWater(World world) {
    PVector totalForce = new PVector(0, 0);
    boolean waterNearby = false;
    float[] distances = {0.5, 1, 1.5};
    float[][] dirs = {
      {1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}
    };
    for (float dist : distances) {
      for (float[] d : dirs) {
        float cx = position.x + d[0] * dist;
        float cy = position.y + d[1] * dist;
        if (!world.isWalkable(cx, cy)) {
          PVector away = new PVector(position.x - cx, position.y - cy);
          float strength = 1.0 / max(away.mag(), 0.5);
          away.normalize();
          away.mult(strength);
          totalForce.add(away);
          waterNearby = true;
        }
      }
    }
    if (waterNearby) {
      acceleration.mult(0);
      totalForce.normalize();
      totalForce.mult(lifecycle.maxForce * 4.0);
      applyForce(totalForce);
    }
  }
}
