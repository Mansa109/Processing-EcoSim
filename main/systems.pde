// ============================================================
//  EcoSim – systems.pde
//  LifecycleSystem: per-creature randomised stats, energy,
//  reproduction readiness, and death.
// ============================================================

class LifecycleSystem {
  float energy;
  float maxEnergy;
  float metabolism;
  float maxSpeed;
  float maxForce;
  float detectionRange;
  float reproductionThreshold;
  float reproductionCost;
  float mateRange;           // how close two creatures must be to breed
  boolean alive = true;
  float hunger;

  // ── Randomised constructor (new creatures / initial spawn) ────
  LifecycleSystem(int initEnergy, boolean predator) {
    maxEnergy = 100;

    if (predator) {
      // Carnivores: faster, hungers faster, sees farther
      metabolism     = random(0.045, 0.070);
      maxSpeed       = random(0.10,  0.14);
      maxForce       = random(0.008, 0.013);
      detectionRange = random(22,    34);
    } else {
      // Herbivores: slower, leaner metabolism, shorter sight
      metabolism     = random(0.020, 0.040);
      maxSpeed       = random(0.07,  0.11);
      maxForce       = random(0.006, 0.010);
      detectionRange = random(16,    26);
    }

    reproductionThreshold = 75;   // energy needed to attempt mating
    reproductionCost      = 25;   // energy spent per parent on birth
    mateRange             = 2.25;  // world-units

    energy = initEnergy;
  }

  // ── Explicit constructor (used by crossbreed()) ───────────────
  LifecycleSystem(float e, float me, float met, float ms, float mf,
                  float dr, float rt, float rc, float mr) {
    energy                = e;
    maxEnergy             = me;
    metabolism            = met;
    maxSpeed              = ms;
    maxForce              = mf;
    detectionRange        = dr;
    reproductionThreshold = rt;
    reproductionCost      = rc;
    mateRange             = mr;
    alive                 = true;
  }

  // ── Instance helpers ──────────────────────────────────────────
  void changeEnergy(float amount) {
    energy = constrain(energy + amount, 0, maxEnergy);
  }

  boolean canReproduce() {
    return alive && energy >= reproductionThreshold;
  }

  void die() {
    alive = false;
  }
}

// ── Top-level: build a child genome from two parent lifecycles ──
// Kept outside the class so Processing's random() is accessible
// without any static-method restrictions.
LifecycleSystem crossbreed(LifecycleSystem a, LifecycleSystem b) {
  float mut = 0.08;  // ±8 % mutation on each averaged trait

  float newMet = constrain(lcAvg(a.metabolism,     b.metabolism)     * lcRandMut(mut), 0.020, 0.100);
  float newMs  = constrain(lcAvg(a.maxSpeed,       b.maxSpeed)       * lcRandMut(mut), 0.040, 0.200);
  float newMf  = constrain(lcAvg(a.maxForce,       b.maxForce)       * lcRandMut(mut), 0.004, 0.020);
  float newDr  = constrain(lcAvg(a.detectionRange, b.detectionRange) * lcRandMut(mut), 8,     45);

  float startEnergy = lcAvg(a.reproductionCost, b.reproductionCost) * 0.9;

  return new LifecycleSystem(
    startEnergy,
    100,                       // maxEnergy
    newMet, newMs, newMf, newDr,
    a.reproductionThreshold,   // inherited unchanged
    a.reproductionCost,
    a.mateRange
  );
}

float lcAvg(float a, float b)      { return (a + b) * 0.5; }
float lcRandMut(float spread)      { return 1.0 + random(-spread, spread); }
