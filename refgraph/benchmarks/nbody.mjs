// This benchmark is derived from nbody.rb and nbody.js
// in Stefan Marr's "Are We Fast Yet?" benchmark.
//   https://github.com/smarr/are-we-fast-yet
// Only the instances of Body are allocated in Ruby
// while the other instances are in JavaScript.

// The Computer Language Benchmarks Game
// http://shootout.alioth.debian.org/
//
//     contributed by Mark C. Lewis
// modified slightly by Chad Whipkey
//
// Based on nbody.java ported to SOM, and then JavaScript by Stefan Marr.

'use strict';

export async function benchmark(n, innerIterations) {
  var result;
  for (var i = 0; i < n; i++) {
    var system = new NBodySystem();
    await system.init();
    for (var j = 0; j < innerIterations; j++) {
      await system.advance(0.01);
    }
    result = await system.energy();
  }

  return result;
}

var
  PI = 3.141592653589793,
  SOLAR_MASS = 4 * PI * PI,
  DAYS_PER_YER = 365.24;

function NBodySystem () {}

NBodySystem.prototype.init = async function () {
  this.bodies = await this.createBodies();
}

NBodySystem.prototype.createBodies = async function () {
  var bodyClass = await Ruby.exec('Body');
  var bodies = [await bodyClass.sun(),
                await bodyClass.jupiter(),
                await bodyClass.saturn(),
                await bodyClass.uranus(),
                await bodyClass.neptune()];

  var px = 0.0,
    py   = 0.0,
    pz   = 0.0;

  var nbodySysClass = await Ruby.exec('NBodySystem');
  for (var i = 0; i < bodies.length; i++) {
    var offset = await nbodySysClass.computeOffset(bodies[i]);
    px += offset[0];
    py += offset[1];
    pz += offset[2];
  }

  await bodies[0].offsetMomentum(px, py, pz);

  return bodies;
};

NBodySystem.prototype.advance = async function (dt) {
  var ruby = await Ruby.exec('NBodySystem');
  for (var i = 0; i < this.bodies.length; ++i) {
    var iBody = this.bodies[i];

    for (var j = i + 1; j < this.bodies.length; ++j) {
      var jBody = this.bodies[j];
      await ruby.advanceBody(dt, iBody, jBody);
    }
  }

  for (var k = 0; k < this.bodies.length; ++k) {
    await ruby.advanceBody2(dt, this.bodies[k]);
  }
};

NBodySystem.prototype.energy = async function () {
  var
    e = 0.0;

  var ruby = await Ruby.exec('NBodySystem');
  for (var i = 0; i < this.bodies.length; ++i) {
    var iBody = this.bodies[i];
    e += await ruby.energyValue(iBody);

    for (var j = i + 1; j < this.bodies.length; ++j) {
      var jBody = this.bodies[j];
      e -= await ruby.energyValue2(iBody, jBody);
    }
  }
  return e;
};
