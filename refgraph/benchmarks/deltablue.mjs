// This benchmark is derived from deltablue.rb and deltablue.js
// in Stefan Marr's "Are We Fast Yet?" benchmark.
//   https://github.com/smarr/are-we-fast-yet

// The benchmark in its current state is a derivation from the SOM version,
// which is derived from Mario Wolczko's Smalltalk version of DeltaBlue.
//
// The original license details are available here:
// http://web.archive.org/web/20050825101121/http://www.sunlabs.com/people/mario/java_benchmarking/index.html
'use strict';

import * as som from './som.mjs';

var rubyFactory;  // an instnace of Factory in Ruby
var strengthAbsoluteWeakest;   // Strength.absoluteWeakest

export async function benchmark(innerIterations) {
  //Ruby.setDebugLevel(10)
  rubyFactory = await Ruby.exec('Factory.new');
  strengthAbsoluteWeakest = await rubyFactory.absoluteWeakest();
  await Planner.chainTest(innerIterations);
  await Planner.projectionTest(innerIterations);
  return true;
}

function Planner() {
  this.currentMark = 1;
}

function Sym(hash) {
  this.hash = hash;
}

Sym.prototype.customHash = function () {
  return this.hash;
};

var ABSOLUTE_STRONGEST = new Sym(0),
  REQUIRED             = new Sym(1),
  STRONG_PREFERRED     = new Sym(2),
  PREFERRED            = new Sym(3),
  STRONG_DEFAULT       = new Sym(4),
  DEFAULT              = new Sym(5),
  WEAK_DEFAULT         = new Sym(6),
  ABSOLUTE_WEAKEST     = new Sym(7);

function Plan() {
  som.Vector.call(this, 15);
}
Plan.prototype = Object.create(som.Vector.prototype);

Plan.prototype.execute = async function () {
  await this.asyncForEach(async function (c) { await c.execute(); });
};

Planner.prototype.newMark = function () {
  this.currentMark += 1;
  return this.currentMark;
};

Planner.prototype.incrementalAdd = Planner.prototype.incremental_add = async function (c) {
  var mark = this.newMark(),
    overridden = await c.satisfy(mark, this);
  while (overridden !== null) {
    overridden = await overridden.satisfy(mark, this);
  }
};

Planner.prototype.incrementalRemove = Planner.prototype.incremental_remove = async function (c) {
  var out = await c.getOutput();
  await c.markUnsatisfied();
  await c.removeFromGraph();

  var unsatisfied = await this.removePropagateFrom(out),
    that = this;
  await unsatisfied.asyncForEach(async function (u) { await that.incrementalAdd(u); });
};

Planner.prototype.extractPlanFromConstraints = async function (constraints) {
  var sources = new som.Vector();
  await constraints.asyncForEach(async function (c) {
    if ((await c.isInput()) && await c.isSatisfied()) {
      sources.append(c);
    }
  });
  return await this.makePlan(sources);
};

Planner.prototype.makePlan = async function (sources) {
  var mark = this.newMark(),
    plan = new Plan(),
    todo = sources;

  while (!todo.isEmpty()) {
    var c = todo.removeFirst();
    if ((await c.getOutput()).mark !== mark && await c.inputsKnown(mark)) {
      // not in plan already and eligible for inclusion
      plan.append(c);
      var v = await c.getOutput();
      v.mark = mark;
      await this.addConstraintsConsumingTo(v, todo);
    }
  }
  return plan;
};

Planner.prototype.propagateFrom = async function (v) {
  var todo = new som.Vector();
  await this.addConstraintsConsumingTo(v, todo);

  while (!todo.isEmpty()) {
    var c = todo.removeFirst();
    await c.execute();
    await this.addConstraintsConsumingTo(c.getOutput(), todo);
  }
};

Planner.prototype.addConstraintsConsumingTo = async function (v, coll) {
  var determiningC = v.determinedBy;

  await v.constraints.asyncForEach(async function (c) {
    if (c !== determiningC && await c.isSatisfied()) {
      coll.append(c);
    }
  });
};

Planner.prototype.addPropagate = Planner.prototype.add_propagate = async function (c, mark) {
  var todo = som.Vector.with(c);

  while (!todo.isEmpty()) {
    var d = todo.removeFirst();

    if ((await d.getOutput()).mark === mark) {
      await this.incrementalRemove(c);
      return false;
    }
    await d.recalculate();
    await this.addConstraintsConsumingTo(await d.getOutput(), todo);
  }
  return true;
};

Planner.prototype.change = async function (v, newValue) {
  var editC = await rubyFactory.editConstraint(v, PREFERRED.customHash(), this),
    editV = som.Vector.with(editC),
    plan = await this.extractPlanFromConstraints(editV);

  for (var i = 0; i < 10; i++) {
    v.value = newValue;
    await plan.execute();
  }
  await editC.destroyConstraint(this);
};

Planner.prototype.constraintsConsuming = async function (v, fn) {
  var determiningC = v.determinedBy;
  await v.constraints.asyncForEach(async function (c) {
    if (c != determiningC && await c.isSatisfied()) {
      await fn(c);
    }
  });
};

Planner.prototype.removePropagateFrom = async function(out) {
  var unsatisfied = new som.Vector();

  out.determinedBy = null;
  out.walkStrength = strengthAbsoluteWeakest;
  out.stay = true;

  var todo = som.Vector.with(out);

  while (!todo.isEmpty()) {
    var v = todo.removeFirst();

    await v.constraints.asyncForEach(async function (c) {
        if (!await c.isSatisfied()) { unsatisfied.append(c); }});

    await this.constraintsConsuming(v, async function (c) {
      await c.recalculate();
      todo.append(await c.getOutput());
    });
  }

  // unsatisfied.sort(function (c1, c2) {
  //  return c1.strength.stronger(c2.strength); });
  // return unsatisfied;
  var arr = unsatisfied.toArray();
  return unsatisfied.initialize(await rubyFactory.sort(arr));
};

Planner.chainTest = async function (n) {
  var planner = new Planner(),
    vars = new Array(n + 1),
    i = 0;

  for (i = 0; i < n + 1; i++) {
    vars[i] = new Variable();
  }

  // Build chain of n equality constraints
  for (i = 0; i < n; i++) {
    var v1 = vars[i],
      v2 = vars[i + 1];
    await rubyFactory.equalityConstraint(v1, v2, REQUIRED.customHash(), planner);
  }

  await rubyFactory.stayConstraint(vars[n], STRONG_DEFAULT.customHash(), planner);
  var editC = await rubyFactory.editConstraint(vars[0], PREFERRED.customHash(), planner),
    editV = som.Vector.with(editC),
    plan = await planner.extractPlanFromConstraints(editV);

  for (i = 0; i < 100; i++) {
    vars[0].value = i;
    await plan.execute();
    if (vars[n].value != i) {
      throw new Error(`Chain test failed! vars[n].value=${vars[n].value}, i=${i}`);
    }
  }
  await editC.destroyConstraint(planner);
};

Planner.projectionTest = async function(n) {
  var planner = new Planner(),
    dests  = new som.Vector(),
    scale  = Variable.value(10),
    offset = Variable.value(1000),

    src = null, dst = null,
    i;

  for (i = 1; i <= n; i++) {
    src = Variable.value(i);
    dst = Variable.value(i);
    dests.append(dst);
    await rubyFactory.stayConstraint(src, DEFAULT.customHash(), planner);
    await rubyFactory.scaleConstraint(src, scale, offset, dst, REQUIRED.customHash(), planner);
  }

  await planner.change(src, 17);
  if (dst.value != 1170) {
    throw new Error("Projection test 1 failed!");
  }

  await planner.change(dst, 1050);
  if (src.value != 5) {
    throw new Error("Projection test 2 failed!");
  }

  await planner.change(scale, 5);
  for (i = 0; i < n - 1; ++i) {
    if (dests.at(i).value != (i + 1) * 5 + 1000) {
      throw new Error("Projection test 3 failed!");
    }
  }

  await planner.change(offset, 2000);
  for (i = 0; i < n - 1; ++i) {
    if (dests.at(i).value != (i + 1) * 5 + 2000) {
      throw new Error("Projection test 4 failed!");
    }
  }
};

function Variable() {
  this.value = 0;
  this.constraints = new som.Vector(2);
  this.determinedBy = null;
  this.walkStrength = strengthAbsoluteWeakest;
  this.stay = true;
  this.mark = 0;
}

Variable.prototype.add_constraint = function (c) {
  this.constraints.append(c);
};

Variable.prototype.remove_constraint = function (c) {
  this.constraints.remove(c);
  if (this.determinedBy == c) {
    this.determinedBy = null;
  }
};

Variable.prototype.set_mark = function (m) {
  this.mark = m;
}

Variable.prototype.walk_strength = function () {
  return this.walkStrength;
}

Variable.prototype.set_walk_strength = function (w) {
  this.walkStrength = w;
}

Variable.prototype.determined_by = function () {
  return this.determinedBy;
}

Variable.prototype.set_determined_by = function (d) {
  this.determinedBy = d;
}

Variable.value = function (aValue) {
  var v = new Variable();
  v.value = aValue;
  return v;
};

