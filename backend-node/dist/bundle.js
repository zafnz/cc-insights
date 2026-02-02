// dist/index.js
import { execSync } from "child_process";
import * as readline from "readline";
import * as fs2 from "fs";

// node_modules/uuid/dist/esm-node/rng.js
import crypto from "crypto";
var rnds8Pool = new Uint8Array(256);
var poolPtr = rnds8Pool.length;
function rng() {
  if (poolPtr > rnds8Pool.length - 16) {
    crypto.randomFillSync(rnds8Pool);
    poolPtr = 0;
  }
  return rnds8Pool.slice(poolPtr, poolPtr += 16);
}

// node_modules/uuid/dist/esm-node/stringify.js
var byteToHex = [];
for (let i2 = 0; i2 < 256; ++i2) {
  byteToHex.push((i2 + 256).toString(16).slice(1));
}
function unsafeStringify(arr, offset = 0) {
  return byteToHex[arr[offset + 0]] + byteToHex[arr[offset + 1]] + byteToHex[arr[offset + 2]] + byteToHex[arr[offset + 3]] + "-" + byteToHex[arr[offset + 4]] + byteToHex[arr[offset + 5]] + "-" + byteToHex[arr[offset + 6]] + byteToHex[arr[offset + 7]] + "-" + byteToHex[arr[offset + 8]] + byteToHex[arr[offset + 9]] + "-" + byteToHex[arr[offset + 10]] + byteToHex[arr[offset + 11]] + byteToHex[arr[offset + 12]] + byteToHex[arr[offset + 13]] + byteToHex[arr[offset + 14]] + byteToHex[arr[offset + 15]];
}

// node_modules/uuid/dist/esm-node/native.js
import crypto2 from "crypto";
var native_default = {
  randomUUID: crypto2.randomUUID
};

// node_modules/uuid/dist/esm-node/v4.js
function v4(options, buf, offset) {
  if (native_default.randomUUID && !buf && !options) {
    return native_default.randomUUID();
  }
  options = options || {};
  const rnds = options.random || (options.rng || rng)();
  rnds[6] = rnds[6] & 15 | 64;
  rnds[8] = rnds[8] & 63 | 128;
  if (buf) {
    offset = offset || 0;
    for (let i2 = 0; i2 < 16; ++i2) {
      buf[offset + i2] = rnds[i2];
    }
    return buf;
  }
  return unsafeStringify(rnds);
}
var v4_default = v4;

// node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs
import { join as rz } from "path";
import { fileURLToPath as EE } from "url";
import { setMaxListeners as GK } from "events";
import { spawn as dU } from "child_process";
import { createInterface as iU } from "readline";
import * as f from "fs";
import { stat as _U, open as ab } from "fs/promises";
import { join as wU } from "path";
import { homedir as MU } from "os";
import { dirname as z8, join as $W } from "path";
import { cwd as jU } from "process";
import { realpathSync as RU } from "fs";
import { randomUUID as EU } from "crypto";
import { randomUUID as uU } from "crypto";
import { appendFileSync as lU, existsSync as mU, mkdirSync as cU } from "fs";
import { join as JW } from "path";
import { randomUUID as rU } from "crypto";
var XK = Object.create;
var { getPrototypeOf: QK, defineProperty: Y8, getOwnPropertyNames: $K } = Object;
var YK = Object.prototype.hasOwnProperty;
var K7 = (X, Q, $) => {
  $ = X != null ? XK(QK(X)) : {};
  let Y = Q || !X || !X.__esModule ? Y8($, "default", { value: X, enumerable: true }) : $;
  for (let W of $K(X)) if (!YK.call(Y, W)) Y8(Y, W, { get: () => X[W], enumerable: true });
  return Y;
};
var P = (X, Q) => () => (Q || X((Q = { exports: {} }).exports, Q), Q.exports);
var U7 = (X, Q) => {
  for (var $ in Q) Y8(X, $, { get: Q[$], enumerable: true, configurable: true, set: (Y) => Q[$] = () => Y });
};
var WK = Symbol.dispose || Symbol.for("Symbol.dispose");
var JK = Symbol.asyncDispose || Symbol.for("Symbol.asyncDispose");
var fX = P((YG) => {
  Object.defineProperty(YG, "__esModule", { value: true });
  YG.regexpCode = YG.getEsmExportName = YG.getProperty = YG.safeStringify = YG.stringify = YG.strConcat = YG.addCodeArg = YG.str = YG._ = YG.nil = YG._Code = YG.Name = YG.IDENTIFIER = YG._CodeOrName = void 0;
  class D9 {
  }
  YG._CodeOrName = D9;
  YG.IDENTIFIER = /^[a-z$_][a-z$_0-9]*$/i;
  class h6 extends D9 {
    constructor(X) {
      super();
      if (!YG.IDENTIFIER.test(X)) throw Error("CodeGen: name must be a valid identifier");
      this.str = X;
    }
    toString() {
      return this.str;
    }
    emptyStr() {
      return false;
    }
    get names() {
      return { [this.str]: 1 };
    }
  }
  YG.Name = h6;
  class s0 extends D9 {
    constructor(X) {
      super();
      this._items = typeof X === "string" ? [X] : X;
    }
    toString() {
      return this.str;
    }
    emptyStr() {
      if (this._items.length > 1) return false;
      let X = this._items[0];
      return X === "" || X === '""';
    }
    get str() {
      var X;
      return (X = this._str) !== null && X !== void 0 ? X : this._str = this._items.reduce((Q, $) => `${Q}${$}`, "");
    }
    get names() {
      var X;
      return (X = this._names) !== null && X !== void 0 ? X : this._names = this._items.reduce((Q, $) => {
        if ($ instanceof h6) Q[$.str] = (Q[$.str] || 0) + 1;
        return Q;
      }, {});
    }
  }
  YG._Code = s0;
  YG.nil = new s0("");
  function QG(X, ...Q) {
    let $ = [X[0]], Y = 0;
    while (Y < Q.length) s$($, Q[Y]), $.push(X[++Y]);
    return new s0($);
  }
  YG._ = QG;
  var a$ = new s0("+");
  function $G(X, ...Q) {
    let $ = [hX(X[0])], Y = 0;
    while (Y < Q.length) $.push(a$), s$($, Q[Y]), $.push(a$, hX(X[++Y]));
    return BN($), new s0($);
  }
  YG.str = $G;
  function s$(X, Q) {
    if (Q instanceof s0) X.push(...Q._items);
    else if (Q instanceof h6) X.push(Q);
    else X.push(UN(Q));
  }
  YG.addCodeArg = s$;
  function BN(X) {
    let Q = 1;
    while (Q < X.length - 1) {
      if (X[Q] === a$) {
        let $ = zN(X[Q - 1], X[Q + 1]);
        if ($ !== void 0) {
          X.splice(Q - 1, 3, $);
          continue;
        }
        X[Q++] = "+";
      }
      Q++;
    }
  }
  function zN(X, Q) {
    if (Q === '""') return X;
    if (X === '""') return Q;
    if (typeof X == "string") {
      if (Q instanceof h6 || X[X.length - 1] !== '"') return;
      if (typeof Q != "string") return `${X.slice(0, -1)}${Q}"`;
      if (Q[0] === '"') return X.slice(0, -1) + Q.slice(1);
      return;
    }
    if (typeof Q == "string" && Q[0] === '"' && !(X instanceof h6)) return `"${X}${Q.slice(1)}`;
    return;
  }
  function KN(X, Q) {
    return Q.emptyStr() ? X : X.emptyStr() ? Q : $G`${X}${Q}`;
  }
  YG.strConcat = KN;
  function UN(X) {
    return typeof X == "number" || typeof X == "boolean" || X === null ? X : hX(Array.isArray(X) ? X.join(",") : X);
  }
  function VN(X) {
    return new s0(hX(X));
  }
  YG.stringify = VN;
  function hX(X) {
    return JSON.stringify(X).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");
  }
  YG.safeStringify = hX;
  function LN(X) {
    return typeof X == "string" && YG.IDENTIFIER.test(X) ? new s0(`.${X}`) : QG`[${X}]`;
  }
  YG.getProperty = LN;
  function qN(X) {
    if (typeof X == "string" && YG.IDENTIFIER.test(X)) return new s0(`${X}`);
    throw Error(`CodeGen: invalid export name: ${X}, use explicit $id name mapping`);
  }
  YG.getEsmExportName = qN;
  function FN(X) {
    return new s0(X.toString());
  }
  YG.regexpCode = FN;
});
var $Y = P((HG) => {
  Object.defineProperty(HG, "__esModule", { value: true });
  HG.ValueScope = HG.ValueScopeName = HG.Scope = HG.varKinds = HG.UsedValueState = void 0;
  var x0 = fX();
  class JG extends Error {
    constructor(X) {
      super(`CodeGen: "code" for ${X} not defined`);
      this.value = X.value;
    }
  }
  var w9;
  (function(X) {
    X[X.Started = 0] = "Started", X[X.Completed = 1] = "Completed";
  })(w9 || (HG.UsedValueState = w9 = {}));
  HG.varKinds = { const: new x0.Name("const"), let: new x0.Name("let"), var: new x0.Name("var") };
  class XY {
    constructor({ prefixes: X, parent: Q } = {}) {
      this._names = {}, this._prefixes = X, this._parent = Q;
    }
    toName(X) {
      return X instanceof x0.Name ? X : this.name(X);
    }
    name(X) {
      return new x0.Name(this._newName(X));
    }
    _newName(X) {
      let Q = this._names[X] || this._nameGroup(X);
      return `${X}${Q.index++}`;
    }
    _nameGroup(X) {
      var Q, $;
      if ((($ = (Q = this._parent) === null || Q === void 0 ? void 0 : Q._prefixes) === null || $ === void 0 ? void 0 : $.has(X)) || this._prefixes && !this._prefixes.has(X)) throw Error(`CodeGen: prefix "${X}" is not allowed in this scope`);
      return this._names[X] = { prefix: X, index: 0 };
    }
  }
  HG.Scope = XY;
  class QY extends x0.Name {
    constructor(X, Q) {
      super(Q);
      this.prefix = X;
    }
    setValue(X, { property: Q, itemIndex: $ }) {
      this.value = X, this.scopePath = x0._`.${new x0.Name(Q)}[${$}]`;
    }
  }
  HG.ValueScopeName = QY;
  var SN = x0._`\n`;
  class GG extends XY {
    constructor(X) {
      super(X);
      this._values = {}, this._scope = X.scope, this.opts = { ...X, _n: X.lines ? SN : x0.nil };
    }
    get() {
      return this._scope;
    }
    name(X) {
      return new QY(X, this._newName(X));
    }
    value(X, Q) {
      var $;
      if (Q.ref === void 0) throw Error("CodeGen: ref must be passed in value");
      let Y = this.toName(X), { prefix: W } = Y, J = ($ = Q.key) !== null && $ !== void 0 ? $ : Q.ref, G = this._values[W];
      if (G) {
        let z = G.get(J);
        if (z) return z;
      } else G = this._values[W] = /* @__PURE__ */ new Map();
      G.set(J, Y);
      let H = this._scope[W] || (this._scope[W] = []), B = H.length;
      return H[B] = Q.ref, Y.setValue(Q, { property: W, itemIndex: B }), Y;
    }
    getValue(X, Q) {
      let $ = this._values[X];
      if (!$) return;
      return $.get(Q);
    }
    scopeRefs(X, Q = this._values) {
      return this._reduceValues(Q, ($) => {
        if ($.scopePath === void 0) throw Error(`CodeGen: name "${$}" has no value`);
        return x0._`${X}${$.scopePath}`;
      });
    }
    scopeCode(X = this._values, Q, $) {
      return this._reduceValues(X, (Y) => {
        if (Y.value === void 0) throw Error(`CodeGen: name "${Y}" has no value`);
        return Y.value.code;
      }, Q, $);
    }
    _reduceValues(X, Q, $ = {}, Y) {
      let W = x0.nil;
      for (let J in X) {
        let G = X[J];
        if (!G) continue;
        let H = $[J] = $[J] || /* @__PURE__ */ new Map();
        G.forEach((B) => {
          if (H.has(B)) return;
          H.set(B, w9.Started);
          let z = Q(B);
          if (z) {
            let K = this.opts.es5 ? HG.varKinds.var : HG.varKinds.const;
            W = x0._`${W}${K} ${B} = ${z};${this.opts._n}`;
          } else if (z = Y === null || Y === void 0 ? void 0 : Y(B)) W = x0._`${W}${z}${this.opts._n}`;
          else throw new JG(B);
          H.set(B, w9.Completed);
        });
      }
      return W;
    }
  }
  HG.ValueScope = GG;
});
var c = P((y0) => {
  Object.defineProperty(y0, "__esModule", { value: true });
  y0.or = y0.and = y0.not = y0.CodeGen = y0.operators = y0.varKinds = y0.ValueScopeName = y0.ValueScope = y0.Scope = y0.Name = y0.regexpCode = y0.stringify = y0.getProperty = y0.nil = y0.strConcat = y0.str = y0._ = void 0;
  var t = fX(), e0 = $Y(), u1 = fX();
  Object.defineProperty(y0, "_", { enumerable: true, get: function() {
    return u1._;
  } });
  Object.defineProperty(y0, "str", { enumerable: true, get: function() {
    return u1.str;
  } });
  Object.defineProperty(y0, "strConcat", { enumerable: true, get: function() {
    return u1.strConcat;
  } });
  Object.defineProperty(y0, "nil", { enumerable: true, get: function() {
    return u1.nil;
  } });
  Object.defineProperty(y0, "getProperty", { enumerable: true, get: function() {
    return u1.getProperty;
  } });
  Object.defineProperty(y0, "stringify", { enumerable: true, get: function() {
    return u1.stringify;
  } });
  Object.defineProperty(y0, "regexpCode", { enumerable: true, get: function() {
    return u1.regexpCode;
  } });
  Object.defineProperty(y0, "Name", { enumerable: true, get: function() {
    return u1.Name;
  } });
  var b9 = $Y();
  Object.defineProperty(y0, "Scope", { enumerable: true, get: function() {
    return b9.Scope;
  } });
  Object.defineProperty(y0, "ValueScope", { enumerable: true, get: function() {
    return b9.ValueScope;
  } });
  Object.defineProperty(y0, "ValueScopeName", { enumerable: true, get: function() {
    return b9.ValueScopeName;
  } });
  Object.defineProperty(y0, "varKinds", { enumerable: true, get: function() {
    return b9.varKinds;
  } });
  y0.operators = { GT: new t._Code(">"), GTE: new t._Code(">="), LT: new t._Code("<"), LTE: new t._Code("<="), EQ: new t._Code("==="), NEQ: new t._Code("!=="), NOT: new t._Code("!"), OR: new t._Code("||"), AND: new t._Code("&&"), ADD: new t._Code("+") };
  class l1 {
    optimizeNodes() {
      return this;
    }
    optimizeNames(X, Q) {
      return this;
    }
  }
  class zG extends l1 {
    constructor(X, Q, $) {
      super();
      this.varKind = X, this.name = Q, this.rhs = $;
    }
    render({ es5: X, _n: Q }) {
      let $ = X ? e0.varKinds.var : this.varKind, Y = this.rhs === void 0 ? "" : ` = ${this.rhs}`;
      return `${$} ${this.name}${Y};` + Q;
    }
    optimizeNames(X, Q) {
      if (!X[this.name.str]) return;
      if (this.rhs) this.rhs = u6(this.rhs, X, Q);
      return this;
    }
    get names() {
      return this.rhs instanceof t._CodeOrName ? this.rhs.names : {};
    }
  }
  class JY extends l1 {
    constructor(X, Q, $) {
      super();
      this.lhs = X, this.rhs = Q, this.sideEffects = $;
    }
    render({ _n: X }) {
      return `${this.lhs} = ${this.rhs};` + X;
    }
    optimizeNames(X, Q) {
      if (this.lhs instanceof t.Name && !X[this.lhs.str] && !this.sideEffects) return;
      return this.rhs = u6(this.rhs, X, Q), this;
    }
    get names() {
      let X = this.lhs instanceof t.Name ? {} : { ...this.lhs.names };
      return I9(X, this.rhs);
    }
  }
  class KG extends JY {
    constructor(X, Q, $, Y) {
      super(X, $, Y);
      this.op = Q;
    }
    render({ _n: X }) {
      return `${this.lhs} ${this.op}= ${this.rhs};` + X;
    }
  }
  class UG extends l1 {
    constructor(X) {
      super();
      this.label = X, this.names = {};
    }
    render({ _n: X }) {
      return `${this.label}:` + X;
    }
  }
  class VG extends l1 {
    constructor(X) {
      super();
      this.label = X, this.names = {};
    }
    render({ _n: X }) {
      return `break${this.label ? ` ${this.label}` : ""};` + X;
    }
  }
  class LG extends l1 {
    constructor(X) {
      super();
      this.error = X;
    }
    render({ _n: X }) {
      return `throw ${this.error};` + X;
    }
    get names() {
      return this.error.names;
    }
  }
  class qG extends l1 {
    constructor(X) {
      super();
      this.code = X;
    }
    render({ _n: X }) {
      return `${this.code};` + X;
    }
    optimizeNodes() {
      return `${this.code}` ? this : void 0;
    }
    optimizeNames(X, Q) {
      return this.code = u6(this.code, X, Q), this;
    }
    get names() {
      return this.code instanceof t._CodeOrName ? this.code.names : {};
    }
  }
  class P9 extends l1 {
    constructor(X = []) {
      super();
      this.nodes = X;
    }
    render(X) {
      return this.nodes.reduce((Q, $) => Q + $.render(X), "");
    }
    optimizeNodes() {
      let { nodes: X } = this, Q = X.length;
      while (Q--) {
        let $ = X[Q].optimizeNodes();
        if (Array.isArray($)) X.splice(Q, 1, ...$);
        else if ($) X[Q] = $;
        else X.splice(Q, 1);
      }
      return X.length > 0 ? this : void 0;
    }
    optimizeNames(X, Q) {
      let { nodes: $ } = this, Y = $.length;
      while (Y--) {
        let W = $[Y];
        if (W.optimizeNames(X, Q)) continue;
        vN(X, W.names), $.splice(Y, 1);
      }
      return $.length > 0 ? this : void 0;
    }
    get names() {
      return this.nodes.reduce((X, Q) => J6(X, Q.names), {});
    }
  }
  class m1 extends P9 {
    render(X) {
      return "{" + X._n + super.render(X) + "}" + X._n;
    }
  }
  class FG extends P9 {
  }
  class uX extends m1 {
  }
  uX.kind = "else";
  class j1 extends m1 {
    constructor(X, Q) {
      super(Q);
      this.condition = X;
    }
    render(X) {
      let Q = `if(${this.condition})` + super.render(X);
      if (this.else) Q += "else " + this.else.render(X);
      return Q;
    }
    optimizeNodes() {
      super.optimizeNodes();
      let X = this.condition;
      if (X === true) return this.nodes;
      let Q = this.else;
      if (Q) {
        let $ = Q.optimizeNodes();
        Q = this.else = Array.isArray($) ? new uX($) : $;
      }
      if (Q) {
        if (X === false) return Q instanceof j1 ? Q : Q.nodes;
        if (this.nodes.length) return this;
        return new j1(wG(X), Q instanceof j1 ? [Q] : Q.nodes);
      }
      if (X === false || !this.nodes.length) return;
      return this;
    }
    optimizeNames(X, Q) {
      var $;
      if (this.else = ($ = this.else) === null || $ === void 0 ? void 0 : $.optimizeNames(X, Q), !(super.optimizeNames(X, Q) || this.else)) return;
      return this.condition = u6(this.condition, X, Q), this;
    }
    get names() {
      let X = super.names;
      if (I9(X, this.condition), this.else) J6(X, this.else.names);
      return X;
    }
  }
  j1.kind = "if";
  class f6 extends m1 {
  }
  f6.kind = "for";
  class NG extends f6 {
    constructor(X) {
      super();
      this.iteration = X;
    }
    render(X) {
      return `for(${this.iteration})` + super.render(X);
    }
    optimizeNames(X, Q) {
      if (!super.optimizeNames(X, Q)) return;
      return this.iteration = u6(this.iteration, X, Q), this;
    }
    get names() {
      return J6(super.names, this.iteration.names);
    }
  }
  class OG extends f6 {
    constructor(X, Q, $, Y) {
      super();
      this.varKind = X, this.name = Q, this.from = $, this.to = Y;
    }
    render(X) {
      let Q = X.es5 ? e0.varKinds.var : this.varKind, { name: $, from: Y, to: W } = this;
      return `for(${Q} ${$}=${Y}; ${$}<${W}; ${$}++)` + super.render(X);
    }
    get names() {
      let X = I9(super.names, this.from);
      return I9(X, this.to);
    }
  }
  class YY extends f6 {
    constructor(X, Q, $, Y) {
      super();
      this.loop = X, this.varKind = Q, this.name = $, this.iterable = Y;
    }
    render(X) {
      return `for(${this.varKind} ${this.name} ${this.loop} ${this.iterable})` + super.render(X);
    }
    optimizeNames(X, Q) {
      if (!super.optimizeNames(X, Q)) return;
      return this.iterable = u6(this.iterable, X, Q), this;
    }
    get names() {
      return J6(super.names, this.iterable.names);
    }
  }
  class M9 extends m1 {
    constructor(X, Q, $) {
      super();
      this.name = X, this.args = Q, this.async = $;
    }
    render(X) {
      return `${this.async ? "async " : ""}function ${this.name}(${this.args})` + super.render(X);
    }
  }
  M9.kind = "func";
  class j9 extends P9 {
    render(X) {
      return "return " + super.render(X);
    }
  }
  j9.kind = "return";
  class DG extends m1 {
    render(X) {
      let Q = "try" + super.render(X);
      if (this.catch) Q += this.catch.render(X);
      if (this.finally) Q += this.finally.render(X);
      return Q;
    }
    optimizeNodes() {
      var X, Q;
      return super.optimizeNodes(), (X = this.catch) === null || X === void 0 || X.optimizeNodes(), (Q = this.finally) === null || Q === void 0 || Q.optimizeNodes(), this;
    }
    optimizeNames(X, Q) {
      var $, Y;
      return super.optimizeNames(X, Q), ($ = this.catch) === null || $ === void 0 || $.optimizeNames(X, Q), (Y = this.finally) === null || Y === void 0 || Y.optimizeNames(X, Q), this;
    }
    get names() {
      let X = super.names;
      if (this.catch) J6(X, this.catch.names);
      if (this.finally) J6(X, this.finally.names);
      return X;
    }
  }
  class R9 extends m1 {
    constructor(X) {
      super();
      this.error = X;
    }
    render(X) {
      return `catch(${this.error})` + super.render(X);
    }
  }
  R9.kind = "catch";
  class E9 extends m1 {
    render(X) {
      return "finally" + super.render(X);
    }
  }
  E9.kind = "finally";
  class AG {
    constructor(X, Q = {}) {
      this._values = {}, this._blockStarts = [], this._constants = {}, this.opts = { ...Q, _n: Q.lines ? `
` : "" }, this._extScope = X, this._scope = new e0.Scope({ parent: X }), this._nodes = [new FG()];
    }
    toString() {
      return this._root.render(this.opts);
    }
    name(X) {
      return this._scope.name(X);
    }
    scopeName(X) {
      return this._extScope.name(X);
    }
    scopeValue(X, Q) {
      let $ = this._extScope.value(X, Q);
      return (this._values[$.prefix] || (this._values[$.prefix] = /* @__PURE__ */ new Set())).add($), $;
    }
    getScopeValue(X, Q) {
      return this._extScope.getValue(X, Q);
    }
    scopeRefs(X) {
      return this._extScope.scopeRefs(X, this._values);
    }
    scopeCode() {
      return this._extScope.scopeCode(this._values);
    }
    _def(X, Q, $, Y) {
      let W = this._scope.toName(Q);
      if ($ !== void 0 && Y) this._constants[W.str] = $;
      return this._leafNode(new zG(X, W, $)), W;
    }
    const(X, Q, $) {
      return this._def(e0.varKinds.const, X, Q, $);
    }
    let(X, Q, $) {
      return this._def(e0.varKinds.let, X, Q, $);
    }
    var(X, Q, $) {
      return this._def(e0.varKinds.var, X, Q, $);
    }
    assign(X, Q, $) {
      return this._leafNode(new JY(X, Q, $));
    }
    add(X, Q) {
      return this._leafNode(new KG(X, y0.operators.ADD, Q));
    }
    code(X) {
      if (typeof X == "function") X();
      else if (X !== t.nil) this._leafNode(new qG(X));
      return this;
    }
    object(...X) {
      let Q = ["{"];
      for (let [$, Y] of X) {
        if (Q.length > 1) Q.push(",");
        if (Q.push($), $ !== Y || this.opts.es5) Q.push(":"), (0, t.addCodeArg)(Q, Y);
      }
      return Q.push("}"), new t._Code(Q);
    }
    if(X, Q, $) {
      if (this._blockNode(new j1(X)), Q && $) this.code(Q).else().code($).endIf();
      else if (Q) this.code(Q).endIf();
      else if ($) throw Error('CodeGen: "else" body without "then" body');
      return this;
    }
    elseIf(X) {
      return this._elseNode(new j1(X));
    }
    else() {
      return this._elseNode(new uX());
    }
    endIf() {
      return this._endBlockNode(j1, uX);
    }
    _for(X, Q) {
      if (this._blockNode(X), Q) this.code(Q).endFor();
      return this;
    }
    for(X, Q) {
      return this._for(new NG(X), Q);
    }
    forRange(X, Q, $, Y, W = this.opts.es5 ? e0.varKinds.var : e0.varKinds.let) {
      let J = this._scope.toName(X);
      return this._for(new OG(W, J, Q, $), () => Y(J));
    }
    forOf(X, Q, $, Y = e0.varKinds.const) {
      let W = this._scope.toName(X);
      if (this.opts.es5) {
        let J = Q instanceof t.Name ? Q : this.var("_arr", Q);
        return this.forRange("_i", 0, t._`${J}.length`, (G) => {
          this.var(W, t._`${J}[${G}]`), $(W);
        });
      }
      return this._for(new YY("of", Y, W, Q), () => $(W));
    }
    forIn(X, Q, $, Y = this.opts.es5 ? e0.varKinds.var : e0.varKinds.const) {
      if (this.opts.ownProperties) return this.forOf(X, t._`Object.keys(${Q})`, $);
      let W = this._scope.toName(X);
      return this._for(new YY("in", Y, W, Q), () => $(W));
    }
    endFor() {
      return this._endBlockNode(f6);
    }
    label(X) {
      return this._leafNode(new UG(X));
    }
    break(X) {
      return this._leafNode(new VG(X));
    }
    return(X) {
      let Q = new j9();
      if (this._blockNode(Q), this.code(X), Q.nodes.length !== 1) throw Error('CodeGen: "return" should have one node');
      return this._endBlockNode(j9);
    }
    try(X, Q, $) {
      if (!Q && !$) throw Error('CodeGen: "try" without "catch" and "finally"');
      let Y = new DG();
      if (this._blockNode(Y), this.code(X), Q) {
        let W = this.name("e");
        this._currNode = Y.catch = new R9(W), Q(W);
      }
      if ($) this._currNode = Y.finally = new E9(), this.code($);
      return this._endBlockNode(R9, E9);
    }
    throw(X) {
      return this._leafNode(new LG(X));
    }
    block(X, Q) {
      if (this._blockStarts.push(this._nodes.length), X) this.code(X).endBlock(Q);
      return this;
    }
    endBlock(X) {
      let Q = this._blockStarts.pop();
      if (Q === void 0) throw Error("CodeGen: not in self-balancing block");
      let $ = this._nodes.length - Q;
      if ($ < 0 || X !== void 0 && $ !== X) throw Error(`CodeGen: wrong number of nodes: ${$} vs ${X} expected`);
      return this._nodes.length = Q, this;
    }
    func(X, Q = t.nil, $, Y) {
      if (this._blockNode(new M9(X, Q, $)), Y) this.code(Y).endFunc();
      return this;
    }
    endFunc() {
      return this._endBlockNode(M9);
    }
    optimize(X = 1) {
      while (X-- > 0) this._root.optimizeNodes(), this._root.optimizeNames(this._root.names, this._constants);
    }
    _leafNode(X) {
      return this._currNode.nodes.push(X), this;
    }
    _blockNode(X) {
      this._currNode.nodes.push(X), this._nodes.push(X);
    }
    _endBlockNode(X, Q) {
      let $ = this._currNode;
      if ($ instanceof X || Q && $ instanceof Q) return this._nodes.pop(), this;
      throw Error(`CodeGen: not in block "${Q ? `${X.kind}/${Q.kind}` : X.kind}"`);
    }
    _elseNode(X) {
      let Q = this._currNode;
      if (!(Q instanceof j1)) throw Error('CodeGen: "else" without "if"');
      return this._currNode = Q.else = X, this;
    }
    get _root() {
      return this._nodes[0];
    }
    get _currNode() {
      let X = this._nodes;
      return X[X.length - 1];
    }
    set _currNode(X) {
      let Q = this._nodes;
      Q[Q.length - 1] = X;
    }
  }
  y0.CodeGen = AG;
  function J6(X, Q) {
    for (let $ in Q) X[$] = (X[$] || 0) + (Q[$] || 0);
    return X;
  }
  function I9(X, Q) {
    return Q instanceof t._CodeOrName ? J6(X, Q.names) : X;
  }
  function u6(X, Q, $) {
    if (X instanceof t.Name) return Y(X);
    if (!W(X)) return X;
    return new t._Code(X._items.reduce((J, G) => {
      if (G instanceof t.Name) G = Y(G);
      if (G instanceof t._Code) J.push(...G._items);
      else J.push(G);
      return J;
    }, []));
    function Y(J) {
      let G = $[J.str];
      if (G === void 0 || Q[J.str] !== 1) return J;
      return delete Q[J.str], G;
    }
    function W(J) {
      return J instanceof t._Code && J._items.some((G) => G instanceof t.Name && Q[G.str] === 1 && $[G.str] !== void 0);
    }
  }
  function vN(X, Q) {
    for (let $ in Q) X[$] = (X[$] || 0) - (Q[$] || 0);
  }
  function wG(X) {
    return typeof X == "boolean" || typeof X == "number" || X === null ? !X : t._`!${WY(X)}`;
  }
  y0.not = wG;
  var TN = MG(y0.operators.AND);
  function _N(...X) {
    return X.reduce(TN);
  }
  y0.and = _N;
  var xN = MG(y0.operators.OR);
  function yN(...X) {
    return X.reduce(xN);
  }
  y0.or = yN;
  function MG(X) {
    return (Q, $) => Q === t.nil ? $ : $ === t.nil ? Q : t._`${WY(Q)} ${X} ${WY($)}`;
  }
  function WY(X) {
    return X instanceof t.Name ? X : t._`(${X})`;
  }
});
var e = P((CG) => {
  Object.defineProperty(CG, "__esModule", { value: true });
  CG.checkStrictMode = CG.getErrorPath = CG.Type = CG.useFunc = CG.setEvaluated = CG.evaluatedPropsToName = CG.mergeEvaluated = CG.eachItem = CG.unescapeJsonPointer = CG.escapeJsonPointer = CG.escapeFragment = CG.unescapeFragment = CG.schemaRefOrVal = CG.schemaHasRulesButRef = CG.schemaHasRules = CG.checkUnknownRules = CG.alwaysValidSchema = CG.toHash = void 0;
  var $0 = c(), uN = fX();
  function lN(X) {
    let Q = {};
    for (let $ of X) Q[$] = true;
    return Q;
  }
  CG.toHash = lN;
  function mN(X, Q) {
    if (typeof Q == "boolean") return Q;
    if (Object.keys(Q).length === 0) return true;
    return IG(X, Q), !bG(Q, X.self.RULES.all);
  }
  CG.alwaysValidSchema = mN;
  function IG(X, Q = X.schema) {
    let { opts: $, self: Y } = X;
    if (!$.strictSchema) return;
    if (typeof Q === "boolean") return;
    let W = Y.RULES.keywords;
    for (let J in Q) if (!W[J]) ZG(X, `unknown keyword: "${J}"`);
  }
  CG.checkUnknownRules = IG;
  function bG(X, Q) {
    if (typeof X == "boolean") return !X;
    for (let $ in X) if (Q[$]) return true;
    return false;
  }
  CG.schemaHasRules = bG;
  function cN(X, Q) {
    if (typeof X == "boolean") return !X;
    for (let $ in X) if ($ !== "$ref" && Q.all[$]) return true;
    return false;
  }
  CG.schemaHasRulesButRef = cN;
  function pN({ topSchemaRef: X, schemaPath: Q }, $, Y, W) {
    if (!W) {
      if (typeof $ == "number" || typeof $ == "boolean") return $;
      if (typeof $ == "string") return $0._`${$}`;
    }
    return $0._`${X}${Q}${(0, $0.getProperty)(Y)}`;
  }
  CG.schemaRefOrVal = pN;
  function dN(X) {
    return PG(decodeURIComponent(X));
  }
  CG.unescapeFragment = dN;
  function iN(X) {
    return encodeURIComponent(HY(X));
  }
  CG.escapeFragment = iN;
  function HY(X) {
    if (typeof X == "number") return `${X}`;
    return X.replace(/~/g, "~0").replace(/\//g, "~1");
  }
  CG.escapeJsonPointer = HY;
  function PG(X) {
    return X.replace(/~1/g, "/").replace(/~0/g, "~");
  }
  CG.unescapeJsonPointer = PG;
  function nN(X, Q) {
    if (Array.isArray(X)) for (let $ of X) Q($);
    else Q(X);
  }
  CG.eachItem = nN;
  function RG({ mergeNames: X, mergeToName: Q, mergeValues: $, resultToName: Y }) {
    return (W, J, G, H) => {
      let B = G === void 0 ? J : G instanceof $0.Name ? (J instanceof $0.Name ? X(W, J, G) : Q(W, J, G), G) : J instanceof $0.Name ? (Q(W, G, J), J) : $(J, G);
      return H === $0.Name && !(B instanceof $0.Name) ? Y(W, B) : B;
    };
  }
  CG.mergeEvaluated = { props: RG({ mergeNames: (X, Q, $) => X.if($0._`${$} !== true && ${Q} !== undefined`, () => {
    X.if($0._`${Q} === true`, () => X.assign($, true), () => X.assign($, $0._`${$} || {}`).code($0._`Object.assign(${$}, ${Q})`));
  }), mergeToName: (X, Q, $) => X.if($0._`${$} !== true`, () => {
    if (Q === true) X.assign($, true);
    else X.assign($, $0._`${$} || {}`), BY(X, $, Q);
  }), mergeValues: (X, Q) => X === true ? true : { ...X, ...Q }, resultToName: SG }), items: RG({ mergeNames: (X, Q, $) => X.if($0._`${$} !== true && ${Q} !== undefined`, () => X.assign($, $0._`${Q} === true ? true : ${$} > ${Q} ? ${$} : ${Q}`)), mergeToName: (X, Q, $) => X.if($0._`${$} !== true`, () => X.assign($, Q === true ? true : $0._`${$} > ${Q} ? ${$} : ${Q}`)), mergeValues: (X, Q) => X === true ? true : Math.max(X, Q), resultToName: (X, Q) => X.var("items", Q) }) };
  function SG(X, Q) {
    if (Q === true) return X.var("props", true);
    let $ = X.var("props", $0._`{}`);
    if (Q !== void 0) BY(X, $, Q);
    return $;
  }
  CG.evaluatedPropsToName = SG;
  function BY(X, Q, $) {
    Object.keys($).forEach((Y) => X.assign($0._`${Q}${(0, $0.getProperty)(Y)}`, true));
  }
  CG.setEvaluated = BY;
  var EG = {};
  function rN(X, Q) {
    return X.scopeValue("func", { ref: Q, code: EG[Q.code] || (EG[Q.code] = new uN._Code(Q.code)) });
  }
  CG.useFunc = rN;
  var GY;
  (function(X) {
    X[X.Num = 0] = "Num", X[X.Str = 1] = "Str";
  })(GY || (CG.Type = GY = {}));
  function oN(X, Q, $) {
    if (X instanceof $0.Name) {
      let Y = Q === GY.Num;
      return $ ? Y ? $0._`"[" + ${X} + "]"` : $0._`"['" + ${X} + "']"` : Y ? $0._`"/" + ${X}` : $0._`"/" + ${X}.replace(/~/g, "~0").replace(/\\//g, "~1")`;
    }
    return $ ? (0, $0.getProperty)(X).toString() : "/" + HY(X);
  }
  CG.getErrorPath = oN;
  function ZG(X, Q, $ = X.opts.strictSchema) {
    if (!$) return;
    if (Q = `strict mode: ${Q}`, $ === true) throw Error(Q);
    X.self.logger.warn(Q);
  }
  CG.checkStrictMode = ZG;
});
var R1 = P((vG) => {
  Object.defineProperty(vG, "__esModule", { value: true });
  var P0 = c(), LO = { data: new P0.Name("data"), valCxt: new P0.Name("valCxt"), instancePath: new P0.Name("instancePath"), parentData: new P0.Name("parentData"), parentDataProperty: new P0.Name("parentDataProperty"), rootData: new P0.Name("rootData"), dynamicAnchors: new P0.Name("dynamicAnchors"), vErrors: new P0.Name("vErrors"), errors: new P0.Name("errors"), this: new P0.Name("this"), self: new P0.Name("self"), scope: new P0.Name("scope"), json: new P0.Name("json"), jsonPos: new P0.Name("jsonPos"), jsonLen: new P0.Name("jsonLen"), jsonPart: new P0.Name("jsonPart") };
  vG.default = LO;
});
var lX = P((yG) => {
  Object.defineProperty(yG, "__esModule", { value: true });
  yG.extendErrors = yG.resetErrorsCount = yG.reportExtraError = yG.reportError = yG.keyword$DataError = yG.keywordError = void 0;
  var a = c(), Z9 = e(), v0 = R1();
  yG.keywordError = { message: ({ keyword: X }) => a.str`must pass "${X}" keyword validation` };
  yG.keyword$DataError = { message: ({ keyword: X, schemaType: Q }) => Q ? a.str`"${X}" keyword must be ${Q} ($data)` : a.str`"${X}" keyword is invalid ($data)` };
  function FO(X, Q = yG.keywordError, $, Y) {
    let { it: W } = X, { gen: J, compositeRule: G, allErrors: H } = W, B = xG(X, Q, $);
    if (Y !== null && Y !== void 0 ? Y : G || H) TG(J, B);
    else _G(W, a._`[${B}]`);
  }
  yG.reportError = FO;
  function NO(X, Q = yG.keywordError, $) {
    let { it: Y } = X, { gen: W, compositeRule: J, allErrors: G } = Y, H = xG(X, Q, $);
    if (TG(W, H), !(J || G)) _G(Y, v0.default.vErrors);
  }
  yG.reportExtraError = NO;
  function OO(X, Q) {
    X.assign(v0.default.errors, Q), X.if(a._`${v0.default.vErrors} !== null`, () => X.if(Q, () => X.assign(a._`${v0.default.vErrors}.length`, Q), () => X.assign(v0.default.vErrors, null)));
  }
  yG.resetErrorsCount = OO;
  function DO({ gen: X, keyword: Q, schemaValue: $, data: Y, errsCount: W, it: J }) {
    if (W === void 0) throw Error("ajv implementation error");
    let G = X.name("err");
    X.forRange("i", W, v0.default.errors, (H) => {
      if (X.const(G, a._`${v0.default.vErrors}[${H}]`), X.if(a._`${G}.instancePath === undefined`, () => X.assign(a._`${G}.instancePath`, (0, a.strConcat)(v0.default.instancePath, J.errorPath))), X.assign(a._`${G}.schemaPath`, a.str`${J.errSchemaPath}/${Q}`), J.opts.verbose) X.assign(a._`${G}.schema`, $), X.assign(a._`${G}.data`, Y);
    });
  }
  yG.extendErrors = DO;
  function TG(X, Q) {
    let $ = X.const("err", Q);
    X.if(a._`${v0.default.vErrors} === null`, () => X.assign(v0.default.vErrors, a._`[${$}]`), a._`${v0.default.vErrors}.push(${$})`), X.code(a._`${v0.default.errors}++`);
  }
  function _G(X, Q) {
    let { gen: $, validateName: Y, schemaEnv: W } = X;
    if (W.$async) $.throw(a._`new ${X.ValidationError}(${Q})`);
    else $.assign(a._`${Y}.errors`, Q), $.return(false);
  }
  var G6 = { keyword: new a.Name("keyword"), schemaPath: new a.Name("schemaPath"), params: new a.Name("params"), propertyName: new a.Name("propertyName"), message: new a.Name("message"), schema: new a.Name("schema"), parentSchema: new a.Name("parentSchema") };
  function xG(X, Q, $) {
    let { createErrors: Y } = X.it;
    if (Y === false) return a._`{}`;
    return AO(X, Q, $);
  }
  function AO(X, Q, $ = {}) {
    let { gen: Y, it: W } = X, J = [wO(W, $), MO(X, $)];
    return jO(X, Q, J), Y.object(...J);
  }
  function wO({ errorPath: X }, { instancePath: Q }) {
    let $ = Q ? a.str`${X}${(0, Z9.getErrorPath)(Q, Z9.Type.Str)}` : X;
    return [v0.default.instancePath, (0, a.strConcat)(v0.default.instancePath, $)];
  }
  function MO({ keyword: X, it: { errSchemaPath: Q } }, { schemaPath: $, parentSchema: Y }) {
    let W = Y ? Q : a.str`${Q}/${X}`;
    if ($) W = a.str`${W}${(0, Z9.getErrorPath)($, Z9.Type.Str)}`;
    return [G6.schemaPath, W];
  }
  function jO(X, { params: Q, message: $ }, Y) {
    let { keyword: W, data: J, schemaValue: G, it: H } = X, { opts: B, propertyName: z, topSchemaRef: K, schemaPath: V } = H;
    if (Y.push([G6.keyword, W], [G6.params, typeof Q == "function" ? Q(X) : Q || a._`{}`]), B.messages) Y.push([G6.message, typeof $ == "function" ? $(X) : $]);
    if (B.verbose) Y.push([G6.schema, G], [G6.parentSchema, a._`${K}${V}`], [v0.default.data, J]);
    if (z) Y.push([G6.propertyName, z]);
  }
});
var lG = P((fG) => {
  Object.defineProperty(fG, "__esModule", { value: true });
  fG.boolOrEmptySchema = fG.topBoolOrEmptySchema = void 0;
  var PO = lX(), SO = c(), ZO = R1(), CO = { message: "boolean schema is false" };
  function kO(X) {
    let { gen: Q, schema: $, validateName: Y } = X;
    if ($ === false) hG(X, false);
    else if (typeof $ == "object" && $.$async === true) Q.return(ZO.default.data);
    else Q.assign(SO._`${Y}.errors`, null), Q.return(true);
  }
  fG.topBoolOrEmptySchema = kO;
  function vO(X, Q) {
    let { gen: $, schema: Y } = X;
    if (Y === false) $.var(Q, false), hG(X);
    else $.var(Q, true);
  }
  fG.boolOrEmptySchema = vO;
  function hG(X, Q) {
    let { gen: $, data: Y } = X, W = { gen: $, keyword: "false schema", data: Y, schema: false, schemaCode: false, schemaValue: false, params: {}, it: X };
    (0, PO.reportError)(W, CO, void 0, Q);
  }
});
var KY = P((mG) => {
  Object.defineProperty(mG, "__esModule", { value: true });
  mG.getRules = mG.isJSONType = void 0;
  var _O = ["string", "number", "integer", "boolean", "null", "object", "array"], xO = new Set(_O);
  function yO(X) {
    return typeof X == "string" && xO.has(X);
  }
  mG.isJSONType = yO;
  function gO() {
    let X = { number: { type: "number", rules: [] }, string: { type: "string", rules: [] }, array: { type: "array", rules: [] }, object: { type: "object", rules: [] } };
    return { types: { ...X, integer: true, boolean: true, null: true }, rules: [{ rules: [] }, X.number, X.string, X.array, X.object], post: { rules: [] }, all: {}, keywords: {} };
  }
  mG.getRules = gO;
});
var UY = P((iG) => {
  Object.defineProperty(iG, "__esModule", { value: true });
  iG.shouldUseRule = iG.shouldUseGroup = iG.schemaHasRulesForType = void 0;
  function fO({ schema: X, self: Q }, $) {
    let Y = Q.RULES.types[$];
    return Y && Y !== true && pG(X, Y);
  }
  iG.schemaHasRulesForType = fO;
  function pG(X, Q) {
    return Q.rules.some(($) => dG(X, $));
  }
  iG.shouldUseGroup = pG;
  function dG(X, Q) {
    var $;
    return X[Q.keyword] !== void 0 || (($ = Q.definition.implements) === null || $ === void 0 ? void 0 : $.some((Y) => X[Y] !== void 0));
  }
  iG.shouldUseRule = dG;
});
var mX = P((aG) => {
  Object.defineProperty(aG, "__esModule", { value: true });
  aG.reportTypeError = aG.checkDataTypes = aG.checkDataType = aG.coerceAndCheckDataType = aG.getJSONTypes = aG.getSchemaTypes = aG.DataType = void 0;
  var mO = KY(), cO = UY(), pO = lX(), m = c(), rG = e(), l6;
  (function(X) {
    X[X.Correct = 0] = "Correct", X[X.Wrong = 1] = "Wrong";
  })(l6 || (aG.DataType = l6 = {}));
  function dO(X) {
    let Q = oG(X.type);
    if (Q.includes("null")) {
      if (X.nullable === false) throw Error("type: null contradicts nullable: false");
    } else {
      if (!Q.length && X.nullable !== void 0) throw Error('"nullable" cannot be used without "type"');
      if (X.nullable === true) Q.push("null");
    }
    return Q;
  }
  aG.getSchemaTypes = dO;
  function oG(X) {
    let Q = Array.isArray(X) ? X : X ? [X] : [];
    if (Q.every(mO.isJSONType)) return Q;
    throw Error("type must be JSONType or JSONType[]: " + Q.join(","));
  }
  aG.getJSONTypes = oG;
  function iO(X, Q) {
    let { gen: $, data: Y, opts: W } = X, J = nO(Q, W.coerceTypes), G = Q.length > 0 && !(J.length === 0 && Q.length === 1 && (0, cO.schemaHasRulesForType)(X, Q[0]));
    if (G) {
      let H = LY(Q, Y, W.strictNumbers, l6.Wrong);
      $.if(H, () => {
        if (J.length) rO(X, Q, J);
        else qY(X);
      });
    }
    return G;
  }
  aG.coerceAndCheckDataType = iO;
  var tG = /* @__PURE__ */ new Set(["string", "number", "integer", "boolean", "null"]);
  function nO(X, Q) {
    return Q ? X.filter(($) => tG.has($) || Q === "array" && $ === "array") : [];
  }
  function rO(X, Q, $) {
    let { gen: Y, data: W, opts: J } = X, G = Y.let("dataType", m._`typeof ${W}`), H = Y.let("coerced", m._`undefined`);
    if (J.coerceTypes === "array") Y.if(m._`${G} == 'object' && Array.isArray(${W}) && ${W}.length == 1`, () => Y.assign(W, m._`${W}[0]`).assign(G, m._`typeof ${W}`).if(LY(Q, W, J.strictNumbers), () => Y.assign(H, W)));
    Y.if(m._`${H} !== undefined`);
    for (let z of $) if (tG.has(z) || z === "array" && J.coerceTypes === "array") B(z);
    Y.else(), qY(X), Y.endIf(), Y.if(m._`${H} !== undefined`, () => {
      Y.assign(W, H), oO(X, H);
    });
    function B(z) {
      switch (z) {
        case "string":
          Y.elseIf(m._`${G} == "number" || ${G} == "boolean"`).assign(H, m._`"" + ${W}`).elseIf(m._`${W} === null`).assign(H, m._`""`);
          return;
        case "number":
          Y.elseIf(m._`${G} == "boolean" || ${W} === null
              || (${G} == "string" && ${W} && ${W} == +${W})`).assign(H, m._`+${W}`);
          return;
        case "integer":
          Y.elseIf(m._`${G} === "boolean" || ${W} === null
              || (${G} === "string" && ${W} && ${W} == +${W} && !(${W} % 1))`).assign(H, m._`+${W}`);
          return;
        case "boolean":
          Y.elseIf(m._`${W} === "false" || ${W} === 0 || ${W} === null`).assign(H, false).elseIf(m._`${W} === "true" || ${W} === 1`).assign(H, true);
          return;
        case "null":
          Y.elseIf(m._`${W} === "" || ${W} === 0 || ${W} === false`), Y.assign(H, null);
          return;
        case "array":
          Y.elseIf(m._`${G} === "string" || ${G} === "number"
              || ${G} === "boolean" || ${W} === null`).assign(H, m._`[${W}]`);
      }
    }
  }
  function oO({ gen: X, parentData: Q, parentDataProperty: $ }, Y) {
    X.if(m._`${Q} !== undefined`, () => X.assign(m._`${Q}[${$}]`, Y));
  }
  function VY(X, Q, $, Y = l6.Correct) {
    let W = Y === l6.Correct ? m.operators.EQ : m.operators.NEQ, J;
    switch (X) {
      case "null":
        return m._`${Q} ${W} null`;
      case "array":
        J = m._`Array.isArray(${Q})`;
        break;
      case "object":
        J = m._`${Q} && typeof ${Q} == "object" && !Array.isArray(${Q})`;
        break;
      case "integer":
        J = G(m._`!(${Q} % 1) && !isNaN(${Q})`);
        break;
      case "number":
        J = G();
        break;
      default:
        return m._`typeof ${Q} ${W} ${X}`;
    }
    return Y === l6.Correct ? J : (0, m.not)(J);
    function G(H = m.nil) {
      return (0, m.and)(m._`typeof ${Q} == "number"`, H, $ ? m._`isFinite(${Q})` : m.nil);
    }
  }
  aG.checkDataType = VY;
  function LY(X, Q, $, Y) {
    if (X.length === 1) return VY(X[0], Q, $, Y);
    let W, J = (0, rG.toHash)(X);
    if (J.array && J.object) {
      let G = m._`typeof ${Q} != "object"`;
      W = J.null ? G : m._`!${Q} || ${G}`, delete J.null, delete J.array, delete J.object;
    } else W = m.nil;
    if (J.number) delete J.integer;
    for (let G in J) W = (0, m.and)(W, VY(G, Q, $, Y));
    return W;
  }
  aG.checkDataTypes = LY;
  var tO = { message: ({ schema: X }) => `must be ${X}`, params: ({ schema: X, schemaValue: Q }) => typeof X == "string" ? m._`{type: ${X}}` : m._`{type: ${Q}}` };
  function qY(X) {
    let Q = aO(X);
    (0, pO.reportError)(Q, tO);
  }
  aG.reportTypeError = qY;
  function aO(X) {
    let { gen: Q, data: $, schema: Y } = X, W = (0, rG.schemaRefOrVal)(X, Y, "type");
    return { gen: Q, keyword: "type", data: $, schema: Y.type, schemaCode: W, schemaValue: W, parentSchema: Y, params: {}, it: X };
  }
});
var $3 = P((X3) => {
  Object.defineProperty(X3, "__esModule", { value: true });
  X3.assignDefaults = void 0;
  var m6 = c(), WD = e();
  function JD(X, Q) {
    let { properties: $, items: Y } = X.schema;
    if (Q === "object" && $) for (let W in $) eG(X, W, $[W].default);
    else if (Q === "array" && Array.isArray(Y)) Y.forEach((W, J) => eG(X, J, W.default));
  }
  X3.assignDefaults = JD;
  function eG(X, Q, $) {
    let { gen: Y, compositeRule: W, data: J, opts: G } = X;
    if ($ === void 0) return;
    let H = m6._`${J}${(0, m6.getProperty)(Q)}`;
    if (W) {
      (0, WD.checkStrictMode)(X, `default is ignored for: ${H}`);
      return;
    }
    let B = m6._`${H} === undefined`;
    if (G.useDefaults === "empty") B = m6._`${B} || ${H} === null || ${H} === ""`;
    Y.if(B, m6._`${H} = ${(0, m6.stringify)($)}`);
  }
});
var d0 = P((J3) => {
  Object.defineProperty(J3, "__esModule", { value: true });
  J3.validateUnion = J3.validateArray = J3.usePattern = J3.callValidateCode = J3.schemaProperties = J3.allSchemaProperties = J3.noPropertyInData = J3.propertyInData = J3.isOwnProperty = J3.hasPropFunc = J3.reportMissingProp = J3.checkMissingProp = J3.checkReportMissingProp = void 0;
  var G0 = c(), FY = e(), c1 = R1(), GD = e();
  function HD(X, Q) {
    let { gen: $, data: Y, it: W } = X;
    $.if(OY($, Y, Q, W.opts.ownProperties), () => {
      X.setParams({ missingProperty: G0._`${Q}` }, true), X.error();
    });
  }
  J3.checkReportMissingProp = HD;
  function BD({ gen: X, data: Q, it: { opts: $ } }, Y, W) {
    return (0, G0.or)(...Y.map((J) => (0, G0.and)(OY(X, Q, J, $.ownProperties), G0._`${W} = ${J}`)));
  }
  J3.checkMissingProp = BD;
  function zD(X, Q) {
    X.setParams({ missingProperty: Q }, true), X.error();
  }
  J3.reportMissingProp = zD;
  function Y3(X) {
    return X.scopeValue("func", { ref: Object.prototype.hasOwnProperty, code: G0._`Object.prototype.hasOwnProperty` });
  }
  J3.hasPropFunc = Y3;
  function NY(X, Q, $) {
    return G0._`${Y3(X)}.call(${Q}, ${$})`;
  }
  J3.isOwnProperty = NY;
  function KD(X, Q, $, Y) {
    let W = G0._`${Q}${(0, G0.getProperty)($)} !== undefined`;
    return Y ? G0._`${W} && ${NY(X, Q, $)}` : W;
  }
  J3.propertyInData = KD;
  function OY(X, Q, $, Y) {
    let W = G0._`${Q}${(0, G0.getProperty)($)} === undefined`;
    return Y ? (0, G0.or)(W, (0, G0.not)(NY(X, Q, $))) : W;
  }
  J3.noPropertyInData = OY;
  function W3(X) {
    return X ? Object.keys(X).filter((Q) => Q !== "__proto__") : [];
  }
  J3.allSchemaProperties = W3;
  function UD(X, Q) {
    return W3(Q).filter(($) => !(0, FY.alwaysValidSchema)(X, Q[$]));
  }
  J3.schemaProperties = UD;
  function VD({ schemaCode: X, data: Q, it: { gen: $, topSchemaRef: Y, schemaPath: W, errorPath: J }, it: G }, H, B, z) {
    let K = z ? G0._`${X}, ${Q}, ${Y}${W}` : Q, V = [[c1.default.instancePath, (0, G0.strConcat)(c1.default.instancePath, J)], [c1.default.parentData, G.parentData], [c1.default.parentDataProperty, G.parentDataProperty], [c1.default.rootData, c1.default.rootData]];
    if (G.opts.dynamicRef) V.push([c1.default.dynamicAnchors, c1.default.dynamicAnchors]);
    let L = G0._`${K}, ${$.object(...V)}`;
    return B !== G0.nil ? G0._`${H}.call(${B}, ${L})` : G0._`${H}(${L})`;
  }
  J3.callValidateCode = VD;
  var LD = G0._`new RegExp`;
  function qD({ gen: X, it: { opts: Q } }, $) {
    let Y = Q.unicodeRegExp ? "u" : "", { regExp: W } = Q.code, J = W($, Y);
    return X.scopeValue("pattern", { key: J.toString(), ref: J, code: G0._`${W.code === "new RegExp" ? LD : (0, GD.useFunc)(X, W)}(${$}, ${Y})` });
  }
  J3.usePattern = qD;
  function FD(X) {
    let { gen: Q, data: $, keyword: Y, it: W } = X, J = Q.name("valid");
    if (W.allErrors) {
      let H = Q.let("valid", true);
      return G(() => Q.assign(H, false)), H;
    }
    return Q.var(J, true), G(() => Q.break()), J;
    function G(H) {
      let B = Q.const("len", G0._`${$}.length`);
      Q.forRange("i", 0, B, (z) => {
        X.subschema({ keyword: Y, dataProp: z, dataPropType: FY.Type.Num }, J), Q.if((0, G0.not)(J), H);
      });
    }
  }
  J3.validateArray = FD;
  function ND(X) {
    let { gen: Q, schema: $, keyword: Y, it: W } = X;
    if (!Array.isArray($)) throw Error("ajv implementation error");
    if ($.some((B) => (0, FY.alwaysValidSchema)(W, B)) && !W.opts.unevaluated) return;
    let G = Q.let("valid", false), H = Q.name("_valid");
    Q.block(() => $.forEach((B, z) => {
      let K = X.subschema({ keyword: Y, schemaProp: z, compositeRule: true }, H);
      if (Q.assign(G, G0._`${G} || ${H}`), !X.mergeValidEvaluated(K, H)) Q.if((0, G0.not)(G));
    })), X.result(G, () => X.reset(), () => X.error(true));
  }
  J3.validateUnion = ND;
});
var U3 = P((z3) => {
  Object.defineProperty(z3, "__esModule", { value: true });
  z3.validateKeywordUsage = z3.validSchemaType = z3.funcKeywordCode = z3.macroKeywordCode = void 0;
  var T0 = c(), H6 = R1(), ZD = d0(), CD = lX();
  function kD(X, Q) {
    let { gen: $, keyword: Y, schema: W, parentSchema: J, it: G } = X, H = Q.macro.call(G.self, W, J, G), B = B3($, Y, H);
    if (G.opts.validateSchema !== false) G.self.validateSchema(H, true);
    let z = $.name("valid");
    X.subschema({ schema: H, schemaPath: T0.nil, errSchemaPath: `${G.errSchemaPath}/${Y}`, topSchemaRef: B, compositeRule: true }, z), X.pass(z, () => X.error(true));
  }
  z3.macroKeywordCode = kD;
  function vD(X, Q) {
    var $;
    let { gen: Y, keyword: W, schema: J, parentSchema: G, $data: H, it: B } = X;
    _D(B, Q);
    let z = !H && Q.compile ? Q.compile.call(B.self, J, G, B) : Q.validate, K = B3(Y, W, z), V = Y.let("valid");
    X.block$data(V, L), X.ok(($ = Q.valid) !== null && $ !== void 0 ? $ : V);
    function L() {
      if (Q.errors === false) {
        if (q(), Q.modifying) H3(X);
        N(() => X.error());
      } else {
        let A = Q.async ? U() : F();
        if (Q.modifying) H3(X);
        N(() => TD(X, A));
      }
    }
    function U() {
      let A = Y.let("ruleErrs", null);
      return Y.try(() => q(T0._`await `), (M) => Y.assign(V, false).if(T0._`${M} instanceof ${B.ValidationError}`, () => Y.assign(A, T0._`${M}.errors`), () => Y.throw(M))), A;
    }
    function F() {
      let A = T0._`${K}.errors`;
      return Y.assign(A, null), q(T0.nil), A;
    }
    function q(A = Q.async ? T0._`await ` : T0.nil) {
      let M = B.opts.passContext ? H6.default.this : H6.default.self, R = !("compile" in Q && !H || Q.schema === false);
      Y.assign(V, T0._`${A}${(0, ZD.callValidateCode)(X, K, M, R)}`, Q.modifying);
    }
    function N(A) {
      var M;
      Y.if((0, T0.not)((M = Q.valid) !== null && M !== void 0 ? M : V), A);
    }
  }
  z3.funcKeywordCode = vD;
  function H3(X) {
    let { gen: Q, data: $, it: Y } = X;
    Q.if(Y.parentData, () => Q.assign($, T0._`${Y.parentData}[${Y.parentDataProperty}]`));
  }
  function TD(X, Q) {
    let { gen: $ } = X;
    $.if(T0._`Array.isArray(${Q})`, () => {
      $.assign(H6.default.vErrors, T0._`${H6.default.vErrors} === null ? ${Q} : ${H6.default.vErrors}.concat(${Q})`).assign(H6.default.errors, T0._`${H6.default.vErrors}.length`), (0, CD.extendErrors)(X);
    }, () => X.error());
  }
  function _D({ schemaEnv: X }, Q) {
    if (Q.async && !X.$async) throw Error("async keyword in sync schema");
  }
  function B3(X, Q, $) {
    if ($ === void 0) throw Error(`keyword "${Q}" failed to compile`);
    return X.scopeValue("keyword", typeof $ == "function" ? { ref: $ } : { ref: $, code: (0, T0.stringify)($) });
  }
  function xD(X, Q, $ = false) {
    return !Q.length || Q.some((Y) => Y === "array" ? Array.isArray(X) : Y === "object" ? X && typeof X == "object" && !Array.isArray(X) : typeof X == Y || $ && typeof X > "u");
  }
  z3.validSchemaType = xD;
  function yD({ schema: X, opts: Q, self: $, errSchemaPath: Y }, W, J) {
    if (Array.isArray(W.keyword) ? !W.keyword.includes(J) : W.keyword !== J) throw Error("ajv implementation error");
    let G = W.dependencies;
    if (G === null || G === void 0 ? void 0 : G.some((H) => !Object.prototype.hasOwnProperty.call(X, H))) throw Error(`parent schema must have dependencies of ${J}: ${G.join(",")}`);
    if (W.validateSchema) {
      if (!W.validateSchema(X[J])) {
        let B = `keyword "${J}" value is invalid at path "${Y}": ` + $.errorsText(W.validateSchema.errors);
        if (Q.validateSchema === "log") $.logger.error(B);
        else throw Error(B);
      }
    }
  }
  z3.validateKeywordUsage = yD;
});
var F3 = P((L3) => {
  Object.defineProperty(L3, "__esModule", { value: true });
  L3.extendSubschemaMode = L3.extendSubschemaData = L3.getSubschema = void 0;
  var U1 = c(), V3 = e();
  function uD(X, { keyword: Q, schemaProp: $, schema: Y, schemaPath: W, errSchemaPath: J, topSchemaRef: G }) {
    if (Q !== void 0 && Y !== void 0) throw Error('both "keyword" and "schema" passed, only one allowed');
    if (Q !== void 0) {
      let H = X.schema[Q];
      return $ === void 0 ? { schema: H, schemaPath: U1._`${X.schemaPath}${(0, U1.getProperty)(Q)}`, errSchemaPath: `${X.errSchemaPath}/${Q}` } : { schema: H[$], schemaPath: U1._`${X.schemaPath}${(0, U1.getProperty)(Q)}${(0, U1.getProperty)($)}`, errSchemaPath: `${X.errSchemaPath}/${Q}/${(0, V3.escapeFragment)($)}` };
    }
    if (Y !== void 0) {
      if (W === void 0 || J === void 0 || G === void 0) throw Error('"schemaPath", "errSchemaPath" and "topSchemaRef" are required with "schema"');
      return { schema: Y, schemaPath: W, topSchemaRef: G, errSchemaPath: J };
    }
    throw Error('either "keyword" or "schema" must be passed');
  }
  L3.getSubschema = uD;
  function lD(X, Q, { dataProp: $, dataPropType: Y, data: W, dataTypes: J, propertyName: G }) {
    if (W !== void 0 && $ !== void 0) throw Error('both "data" and "dataProp" passed, only one allowed');
    let { gen: H } = Q;
    if ($ !== void 0) {
      let { errorPath: z, dataPathArr: K, opts: V } = Q, L = H.let("data", U1._`${Q.data}${(0, U1.getProperty)($)}`, true);
      B(L), X.errorPath = U1.str`${z}${(0, V3.getErrorPath)($, Y, V.jsPropertySyntax)}`, X.parentDataProperty = U1._`${$}`, X.dataPathArr = [...K, X.parentDataProperty];
    }
    if (W !== void 0) {
      let z = W instanceof U1.Name ? W : H.let("data", W, true);
      if (B(z), G !== void 0) X.propertyName = G;
    }
    if (J) X.dataTypes = J;
    function B(z) {
      X.data = z, X.dataLevel = Q.dataLevel + 1, X.dataTypes = [], Q.definedProperties = /* @__PURE__ */ new Set(), X.parentData = Q.data, X.dataNames = [...Q.dataNames, z];
    }
  }
  L3.extendSubschemaData = lD;
  function mD(X, { jtdDiscriminator: Q, jtdMetadata: $, compositeRule: Y, createErrors: W, allErrors: J }) {
    if (Y !== void 0) X.compositeRule = Y;
    if (W !== void 0) X.createErrors = W;
    if (J !== void 0) X.allErrors = J;
    X.jtdDiscriminator = Q, X.jtdMetadata = $;
  }
  L3.extendSubschemaMode = mD;
});
var DY = P((mv, N3) => {
  N3.exports = function X(Q, $) {
    if (Q === $) return true;
    if (Q && $ && typeof Q == "object" && typeof $ == "object") {
      if (Q.constructor !== $.constructor) return false;
      var Y, W, J;
      if (Array.isArray(Q)) {
        if (Y = Q.length, Y != $.length) return false;
        for (W = Y; W-- !== 0; ) if (!X(Q[W], $[W])) return false;
        return true;
      }
      if (Q.constructor === RegExp) return Q.source === $.source && Q.flags === $.flags;
      if (Q.valueOf !== Object.prototype.valueOf) return Q.valueOf() === $.valueOf();
      if (Q.toString !== Object.prototype.toString) return Q.toString() === $.toString();
      if (J = Object.keys(Q), Y = J.length, Y !== Object.keys($).length) return false;
      for (W = Y; W-- !== 0; ) if (!Object.prototype.hasOwnProperty.call($, J[W])) return false;
      for (W = Y; W-- !== 0; ) {
        var G = J[W];
        if (!X(Q[G], $[G])) return false;
      }
      return true;
    }
    return Q !== Q && $ !== $;
  };
});
var D3 = P((cv, O3) => {
  var p1 = O3.exports = function(X, Q, $) {
    if (typeof Q == "function") $ = Q, Q = {};
    $ = Q.cb || $;
    var Y = typeof $ == "function" ? $ : $.pre || function() {
    }, W = $.post || function() {
    };
    C9(Q, Y, W, X, "", X);
  };
  p1.keywords = { additionalItems: true, items: true, contains: true, additionalProperties: true, propertyNames: true, not: true, if: true, then: true, else: true };
  p1.arrayKeywords = { items: true, allOf: true, anyOf: true, oneOf: true };
  p1.propsKeywords = { $defs: true, definitions: true, properties: true, patternProperties: true, dependencies: true };
  p1.skipKeywords = { default: true, enum: true, const: true, required: true, maximum: true, minimum: true, exclusiveMaximum: true, exclusiveMinimum: true, multipleOf: true, maxLength: true, minLength: true, pattern: true, format: true, maxItems: true, minItems: true, uniqueItems: true, maxProperties: true, minProperties: true };
  function C9(X, Q, $, Y, W, J, G, H, B, z) {
    if (Y && typeof Y == "object" && !Array.isArray(Y)) {
      Q(Y, W, J, G, H, B, z);
      for (var K in Y) {
        var V = Y[K];
        if (Array.isArray(V)) {
          if (K in p1.arrayKeywords) for (var L = 0; L < V.length; L++) C9(X, Q, $, V[L], W + "/" + K + "/" + L, J, W, K, Y, L);
        } else if (K in p1.propsKeywords) {
          if (V && typeof V == "object") for (var U in V) C9(X, Q, $, V[U], W + "/" + K + "/" + dD(U), J, W, K, Y, U);
        } else if (K in p1.keywords || X.allKeys && !(K in p1.skipKeywords)) C9(X, Q, $, V, W + "/" + K, J, W, K, Y);
      }
      $(Y, W, J, G, H, B, z);
    }
  }
  function dD(X) {
    return X.replace(/~/g, "~0").replace(/\//g, "~1");
  }
});
var cX = P((j3) => {
  Object.defineProperty(j3, "__esModule", { value: true });
  j3.getSchemaRefs = j3.resolveUrl = j3.normalizeId = j3._getFullPath = j3.getFullPath = j3.inlineRef = void 0;
  var iD = e(), nD = DY(), rD = D3(), oD = /* @__PURE__ */ new Set(["type", "format", "pattern", "maxLength", "minLength", "maxProperties", "minProperties", "maxItems", "minItems", "maximum", "minimum", "uniqueItems", "multipleOf", "required", "enum", "const"]);
  function tD(X, Q = true) {
    if (typeof X == "boolean") return true;
    if (Q === true) return !AY(X);
    if (!Q) return false;
    return A3(X) <= Q;
  }
  j3.inlineRef = tD;
  var aD = /* @__PURE__ */ new Set(["$ref", "$recursiveRef", "$recursiveAnchor", "$dynamicRef", "$dynamicAnchor"]);
  function AY(X) {
    for (let Q in X) {
      if (aD.has(Q)) return true;
      let $ = X[Q];
      if (Array.isArray($) && $.some(AY)) return true;
      if (typeof $ == "object" && AY($)) return true;
    }
    return false;
  }
  function A3(X) {
    let Q = 0;
    for (let $ in X) {
      if ($ === "$ref") return 1 / 0;
      if (Q++, oD.has($)) continue;
      if (typeof X[$] == "object") (0, iD.eachItem)(X[$], (Y) => Q += A3(Y));
      if (Q === 1 / 0) return 1 / 0;
    }
    return Q;
  }
  function w3(X, Q = "", $) {
    if ($ !== false) Q = c6(Q);
    let Y = X.parse(Q);
    return M3(X, Y);
  }
  j3.getFullPath = w3;
  function M3(X, Q) {
    return X.serialize(Q).split("#")[0] + "#";
  }
  j3._getFullPath = M3;
  var sD = /#\/?$/;
  function c6(X) {
    return X ? X.replace(sD, "") : "";
  }
  j3.normalizeId = c6;
  function eD(X, Q, $) {
    return $ = c6($), X.resolve(Q, $);
  }
  j3.resolveUrl = eD;
  var XA = /^[a-z_][-a-z0-9._]*$/i;
  function QA(X, Q) {
    if (typeof X == "boolean") return {};
    let { schemaId: $, uriResolver: Y } = this.opts, W = c6(X[$] || Q), J = { "": W }, G = w3(Y, W, false), H = {}, B = /* @__PURE__ */ new Set();
    return rD(X, { allKeys: true }, (V, L, U, F) => {
      if (F === void 0) return;
      let q = G + L, N = J[F];
      if (typeof V[$] == "string") N = A.call(this, V[$]);
      M.call(this, V.$anchor), M.call(this, V.$dynamicAnchor), J[L] = N;
      function A(R) {
        let S = this.opts.uriResolver.resolve;
        if (R = c6(N ? S(N, R) : R), B.has(R)) throw K(R);
        B.add(R);
        let C = this.refs[R];
        if (typeof C == "string") C = this.refs[C];
        if (typeof C == "object") z(V, C.schema, R);
        else if (R !== c6(q)) if (R[0] === "#") z(V, H[R], R), H[R] = V;
        else this.refs[R] = q;
        return R;
      }
      function M(R) {
        if (typeof R == "string") {
          if (!XA.test(R)) throw Error(`invalid anchor "${R}"`);
          A.call(this, `#${R}`);
        }
      }
    }), H;
    function z(V, L, U) {
      if (L !== void 0 && !nD(V, L)) throw K(U);
    }
    function K(V) {
      return Error(`reference "${V}" resolves to more than one schema`);
    }
  }
  j3.getSchemaRefs = QA;
});
var iX = P((h3) => {
  Object.defineProperty(h3, "__esModule", { value: true });
  h3.getData = h3.KeywordCxt = h3.validateFunctionCode = void 0;
  var S3 = lG(), E3 = mX(), MY = UY(), k9 = mX(), HA = $3(), dX = U3(), wY = F3(), _ = c(), u = R1(), BA = cX(), E1 = e(), pX = lX();
  function zA(X) {
    if (k3(X)) {
      if (v3(X), C3(X)) {
        VA(X);
        return;
      }
    }
    Z3(X, () => (0, S3.topBoolOrEmptySchema)(X));
  }
  h3.validateFunctionCode = zA;
  function Z3({ gen: X, validateName: Q, schema: $, schemaEnv: Y, opts: W }, J) {
    if (W.code.es5) X.func(Q, _._`${u.default.data}, ${u.default.valCxt}`, Y.$async, () => {
      X.code(_._`"use strict"; ${I3($, W)}`), UA(X, W), X.code(J);
    });
    else X.func(Q, _._`${u.default.data}, ${KA(W)}`, Y.$async, () => X.code(I3($, W)).code(J));
  }
  function KA(X) {
    return _._`{${u.default.instancePath}="", ${u.default.parentData}, ${u.default.parentDataProperty}, ${u.default.rootData}=${u.default.data}${X.dynamicRef ? _._`, ${u.default.dynamicAnchors}={}` : _.nil}}={}`;
  }
  function UA(X, Q) {
    X.if(u.default.valCxt, () => {
      if (X.var(u.default.instancePath, _._`${u.default.valCxt}.${u.default.instancePath}`), X.var(u.default.parentData, _._`${u.default.valCxt}.${u.default.parentData}`), X.var(u.default.parentDataProperty, _._`${u.default.valCxt}.${u.default.parentDataProperty}`), X.var(u.default.rootData, _._`${u.default.valCxt}.${u.default.rootData}`), Q.dynamicRef) X.var(u.default.dynamicAnchors, _._`${u.default.valCxt}.${u.default.dynamicAnchors}`);
    }, () => {
      if (X.var(u.default.instancePath, _._`""`), X.var(u.default.parentData, _._`undefined`), X.var(u.default.parentDataProperty, _._`undefined`), X.var(u.default.rootData, u.default.data), Q.dynamicRef) X.var(u.default.dynamicAnchors, _._`{}`);
    });
  }
  function VA(X) {
    let { schema: Q, opts: $, gen: Y } = X;
    Z3(X, () => {
      if ($.$comment && Q.$comment) _3(X);
      if (OA(X), Y.let(u.default.vErrors, null), Y.let(u.default.errors, 0), $.unevaluated) LA(X);
      T3(X), wA(X);
    });
    return;
  }
  function LA(X) {
    let { gen: Q, validateName: $ } = X;
    X.evaluated = Q.const("evaluated", _._`${$}.evaluated`), Q.if(_._`${X.evaluated}.dynamicProps`, () => Q.assign(_._`${X.evaluated}.props`, _._`undefined`)), Q.if(_._`${X.evaluated}.dynamicItems`, () => Q.assign(_._`${X.evaluated}.items`, _._`undefined`));
  }
  function I3(X, Q) {
    let $ = typeof X == "object" && X[Q.schemaId];
    return $ && (Q.code.source || Q.code.process) ? _._`/*# sourceURL=${$} */` : _.nil;
  }
  function qA(X, Q) {
    if (k3(X)) {
      if (v3(X), C3(X)) {
        FA(X, Q);
        return;
      }
    }
    (0, S3.boolOrEmptySchema)(X, Q);
  }
  function C3({ schema: X, self: Q }) {
    if (typeof X == "boolean") return !X;
    for (let $ in X) if (Q.RULES.all[$]) return true;
    return false;
  }
  function k3(X) {
    return typeof X.schema != "boolean";
  }
  function FA(X, Q) {
    let { schema: $, gen: Y, opts: W } = X;
    if (W.$comment && $.$comment) _3(X);
    DA(X), AA(X);
    let J = Y.const("_errs", u.default.errors);
    T3(X, J), Y.var(Q, _._`${J} === ${u.default.errors}`);
  }
  function v3(X) {
    (0, E1.checkUnknownRules)(X), NA(X);
  }
  function T3(X, Q) {
    if (X.opts.jtd) return b3(X, [], false, Q);
    let $ = (0, E3.getSchemaTypes)(X.schema), Y = (0, E3.coerceAndCheckDataType)(X, $);
    b3(X, $, !Y, Q);
  }
  function NA(X) {
    let { schema: Q, errSchemaPath: $, opts: Y, self: W } = X;
    if (Q.$ref && Y.ignoreKeywordsWithRef && (0, E1.schemaHasRulesButRef)(Q, W.RULES)) W.logger.warn(`$ref: keywords ignored in schema at path "${$}"`);
  }
  function OA(X) {
    let { schema: Q, opts: $ } = X;
    if (Q.default !== void 0 && $.useDefaults && $.strictSchema) (0, E1.checkStrictMode)(X, "default is ignored in the schema root");
  }
  function DA(X) {
    let Q = X.schema[X.opts.schemaId];
    if (Q) X.baseId = (0, BA.resolveUrl)(X.opts.uriResolver, X.baseId, Q);
  }
  function AA(X) {
    if (X.schema.$async && !X.schemaEnv.$async) throw Error("async schema in sync schema");
  }
  function _3({ gen: X, schemaEnv: Q, schema: $, errSchemaPath: Y, opts: W }) {
    let J = $.$comment;
    if (W.$comment === true) X.code(_._`${u.default.self}.logger.log(${J})`);
    else if (typeof W.$comment == "function") {
      let G = _.str`${Y}/$comment`, H = X.scopeValue("root", { ref: Q.root });
      X.code(_._`${u.default.self}.opts.$comment(${J}, ${G}, ${H}.schema)`);
    }
  }
  function wA(X) {
    let { gen: Q, schemaEnv: $, validateName: Y, ValidationError: W, opts: J } = X;
    if ($.$async) Q.if(_._`${u.default.errors} === 0`, () => Q.return(u.default.data), () => Q.throw(_._`new ${W}(${u.default.vErrors})`));
    else {
      if (Q.assign(_._`${Y}.errors`, u.default.vErrors), J.unevaluated) MA(X);
      Q.return(_._`${u.default.errors} === 0`);
    }
  }
  function MA({ gen: X, evaluated: Q, props: $, items: Y }) {
    if ($ instanceof _.Name) X.assign(_._`${Q}.props`, $);
    if (Y instanceof _.Name) X.assign(_._`${Q}.items`, Y);
  }
  function b3(X, Q, $, Y) {
    let { gen: W, schema: J, data: G, allErrors: H, opts: B, self: z } = X, { RULES: K } = z;
    if (J.$ref && (B.ignoreKeywordsWithRef || !(0, E1.schemaHasRulesButRef)(J, K))) {
      W.block(() => y3(X, "$ref", K.all.$ref.definition));
      return;
    }
    if (!B.jtd) jA(X, Q);
    W.block(() => {
      for (let L of K.rules) V(L);
      V(K.post);
    });
    function V(L) {
      if (!(0, MY.shouldUseGroup)(J, L)) return;
      if (L.type) {
        if (W.if((0, k9.checkDataType)(L.type, G, B.strictNumbers)), P3(X, L), Q.length === 1 && Q[0] === L.type && $) W.else(), (0, k9.reportTypeError)(X);
        W.endIf();
      } else P3(X, L);
      if (!H) W.if(_._`${u.default.errors} === ${Y || 0}`);
    }
  }
  function P3(X, Q) {
    let { gen: $, schema: Y, opts: { useDefaults: W } } = X;
    if (W) (0, HA.assignDefaults)(X, Q.type);
    $.block(() => {
      for (let J of Q.rules) if ((0, MY.shouldUseRule)(Y, J)) y3(X, J.keyword, J.definition, Q.type);
    });
  }
  function jA(X, Q) {
    if (X.schemaEnv.meta || !X.opts.strictTypes) return;
    if (RA(X, Q), !X.opts.allowUnionTypes) EA(X, Q);
    IA(X, X.dataTypes);
  }
  function RA(X, Q) {
    if (!Q.length) return;
    if (!X.dataTypes.length) {
      X.dataTypes = Q;
      return;
    }
    Q.forEach(($) => {
      if (!x3(X.dataTypes, $)) jY(X, `type "${$}" not allowed by context "${X.dataTypes.join(",")}"`);
    }), PA(X, Q);
  }
  function EA(X, Q) {
    if (Q.length > 1 && !(Q.length === 2 && Q.includes("null"))) jY(X, "use allowUnionTypes to allow union type keyword");
  }
  function IA(X, Q) {
    let $ = X.self.RULES.all;
    for (let Y in $) {
      let W = $[Y];
      if (typeof W == "object" && (0, MY.shouldUseRule)(X.schema, W)) {
        let { type: J } = W.definition;
        if (J.length && !J.some((G) => bA(Q, G))) jY(X, `missing type "${J.join(",")}" for keyword "${Y}"`);
      }
    }
  }
  function bA(X, Q) {
    return X.includes(Q) || Q === "number" && X.includes("integer");
  }
  function x3(X, Q) {
    return X.includes(Q) || Q === "integer" && X.includes("number");
  }
  function PA(X, Q) {
    let $ = [];
    for (let Y of X.dataTypes) if (x3(Q, Y)) $.push(Y);
    else if (Q.includes("integer") && Y === "number") $.push("integer");
    X.dataTypes = $;
  }
  function jY(X, Q) {
    let $ = X.schemaEnv.baseId + X.errSchemaPath;
    Q += ` at "${$}" (strictTypes)`, (0, E1.checkStrictMode)(X, Q, X.opts.strictTypes);
  }
  class RY {
    constructor(X, Q, $) {
      if ((0, dX.validateKeywordUsage)(X, Q, $), this.gen = X.gen, this.allErrors = X.allErrors, this.keyword = $, this.data = X.data, this.schema = X.schema[$], this.$data = Q.$data && X.opts.$data && this.schema && this.schema.$data, this.schemaValue = (0, E1.schemaRefOrVal)(X, this.schema, $, this.$data), this.schemaType = Q.schemaType, this.parentSchema = X.schema, this.params = {}, this.it = X, this.def = Q, this.$data) this.schemaCode = X.gen.const("vSchema", g3(this.$data, X));
      else if (this.schemaCode = this.schemaValue, !(0, dX.validSchemaType)(this.schema, Q.schemaType, Q.allowUndefined)) throw Error(`${$} value must be ${JSON.stringify(Q.schemaType)}`);
      if ("code" in Q ? Q.trackErrors : Q.errors !== false) this.errsCount = X.gen.const("_errs", u.default.errors);
    }
    result(X, Q, $) {
      this.failResult((0, _.not)(X), Q, $);
    }
    failResult(X, Q, $) {
      if (this.gen.if(X), $) $();
      else this.error();
      if (Q) {
        if (this.gen.else(), Q(), this.allErrors) this.gen.endIf();
      } else if (this.allErrors) this.gen.endIf();
      else this.gen.else();
    }
    pass(X, Q) {
      this.failResult((0, _.not)(X), void 0, Q);
    }
    fail(X) {
      if (X === void 0) {
        if (this.error(), !this.allErrors) this.gen.if(false);
        return;
      }
      if (this.gen.if(X), this.error(), this.allErrors) this.gen.endIf();
      else this.gen.else();
    }
    fail$data(X) {
      if (!this.$data) return this.fail(X);
      let { schemaCode: Q } = this;
      this.fail(_._`${Q} !== undefined && (${(0, _.or)(this.invalid$data(), X)})`);
    }
    error(X, Q, $) {
      if (Q) {
        this.setParams(Q), this._error(X, $), this.setParams({});
        return;
      }
      this._error(X, $);
    }
    _error(X, Q) {
      (X ? pX.reportExtraError : pX.reportError)(this, this.def.error, Q);
    }
    $dataError() {
      (0, pX.reportError)(this, this.def.$dataError || pX.keyword$DataError);
    }
    reset() {
      if (this.errsCount === void 0) throw Error('add "trackErrors" to keyword definition');
      (0, pX.resetErrorsCount)(this.gen, this.errsCount);
    }
    ok(X) {
      if (!this.allErrors) this.gen.if(X);
    }
    setParams(X, Q) {
      if (Q) Object.assign(this.params, X);
      else this.params = X;
    }
    block$data(X, Q, $ = _.nil) {
      this.gen.block(() => {
        this.check$data(X, $), Q();
      });
    }
    check$data(X = _.nil, Q = _.nil) {
      if (!this.$data) return;
      let { gen: $, schemaCode: Y, schemaType: W, def: J } = this;
      if ($.if((0, _.or)(_._`${Y} === undefined`, Q)), X !== _.nil) $.assign(X, true);
      if (W.length || J.validateSchema) {
        if ($.elseIf(this.invalid$data()), this.$dataError(), X !== _.nil) $.assign(X, false);
      }
      $.else();
    }
    invalid$data() {
      let { gen: X, schemaCode: Q, schemaType: $, def: Y, it: W } = this;
      return (0, _.or)(J(), G());
      function J() {
        if ($.length) {
          if (!(Q instanceof _.Name)) throw Error("ajv implementation error");
          let H = Array.isArray($) ? $ : [$];
          return _._`${(0, k9.checkDataTypes)(H, Q, W.opts.strictNumbers, k9.DataType.Wrong)}`;
        }
        return _.nil;
      }
      function G() {
        if (Y.validateSchema) {
          let H = X.scopeValue("validate$data", { ref: Y.validateSchema });
          return _._`!${H}(${Q})`;
        }
        return _.nil;
      }
    }
    subschema(X, Q) {
      let $ = (0, wY.getSubschema)(this.it, X);
      (0, wY.extendSubschemaData)($, this.it, X), (0, wY.extendSubschemaMode)($, X);
      let Y = { ...this.it, ...$, items: void 0, props: void 0 };
      return qA(Y, Q), Y;
    }
    mergeEvaluated(X, Q) {
      let { it: $, gen: Y } = this;
      if (!$.opts.unevaluated) return;
      if ($.props !== true && X.props !== void 0) $.props = E1.mergeEvaluated.props(Y, X.props, $.props, Q);
      if ($.items !== true && X.items !== void 0) $.items = E1.mergeEvaluated.items(Y, X.items, $.items, Q);
    }
    mergeValidEvaluated(X, Q) {
      let { it: $, gen: Y } = this;
      if ($.opts.unevaluated && ($.props !== true || $.items !== true)) return Y.if(Q, () => this.mergeEvaluated(X, _.Name)), true;
    }
  }
  h3.KeywordCxt = RY;
  function y3(X, Q, $, Y) {
    let W = new RY(X, $, Q);
    if ("code" in $) $.code(W, Y);
    else if (W.$data && $.validate) (0, dX.funcKeywordCode)(W, $);
    else if ("macro" in $) (0, dX.macroKeywordCode)(W, $);
    else if ($.compile || $.validate) (0, dX.funcKeywordCode)(W, $);
  }
  var SA = /^\/(?:[^~]|~0|~1)*$/, ZA = /^([0-9]+)(#|\/(?:[^~]|~0|~1)*)?$/;
  function g3(X, { dataLevel: Q, dataNames: $, dataPathArr: Y }) {
    let W, J;
    if (X === "") return u.default.rootData;
    if (X[0] === "/") {
      if (!SA.test(X)) throw Error(`Invalid JSON-pointer: ${X}`);
      W = X, J = u.default.rootData;
    } else {
      let z = ZA.exec(X);
      if (!z) throw Error(`Invalid JSON-pointer: ${X}`);
      let K = +z[1];
      if (W = z[2], W === "#") {
        if (K >= Q) throw Error(B("property/index", K));
        return Y[Q - K];
      }
      if (K > Q) throw Error(B("data", K));
      if (J = $[Q - K], !W) return J;
    }
    let G = J, H = W.split("/");
    for (let z of H) if (z) J = _._`${J}${(0, _.getProperty)((0, E1.unescapeJsonPointer)(z))}`, G = _._`${G} && ${J}`;
    return G;
    function B(z, K) {
      return `Cannot access ${z} ${K} levels up, current level is ${Q}`;
    }
  }
  h3.getData = g3;
});
var v9 = P((l3) => {
  Object.defineProperty(l3, "__esModule", { value: true });
  class u3 extends Error {
    constructor(X) {
      super("validation failed");
      this.errors = X, this.ajv = this.validation = true;
    }
  }
  l3.default = u3;
});
var nX = P((c3) => {
  Object.defineProperty(c3, "__esModule", { value: true });
  var EY = cX();
  class m3 extends Error {
    constructor(X, Q, $, Y) {
      super(Y || `can't resolve reference ${$} from id ${Q}`);
      this.missingRef = (0, EY.resolveUrl)(X, Q, $), this.missingSchema = (0, EY.normalizeId)((0, EY.getFullPath)(X, this.missingRef));
    }
  }
  c3.default = m3;
});
var _9 = P((i3) => {
  Object.defineProperty(i3, "__esModule", { value: true });
  i3.resolveSchema = i3.getCompilingSchema = i3.resolveRef = i3.compileSchema = i3.SchemaEnv = void 0;
  var X1 = c(), _A = v9(), B6 = R1(), Q1 = cX(), p3 = e(), xA = iX();
  class rX {
    constructor(X) {
      var Q;
      this.refs = {}, this.dynamicAnchors = {};
      let $;
      if (typeof X.schema == "object") $ = X.schema;
      this.schema = X.schema, this.schemaId = X.schemaId, this.root = X.root || this, this.baseId = (Q = X.baseId) !== null && Q !== void 0 ? Q : (0, Q1.normalizeId)($ === null || $ === void 0 ? void 0 : $[X.schemaId || "$id"]), this.schemaPath = X.schemaPath, this.localRefs = X.localRefs, this.meta = X.meta, this.$async = $ === null || $ === void 0 ? void 0 : $.$async, this.refs = {};
    }
  }
  i3.SchemaEnv = rX;
  function bY(X) {
    let Q = d3.call(this, X);
    if (Q) return Q;
    let $ = (0, Q1.getFullPath)(this.opts.uriResolver, X.root.baseId), { es5: Y, lines: W } = this.opts.code, { ownProperties: J } = this.opts, G = new X1.CodeGen(this.scope, { es5: Y, lines: W, ownProperties: J }), H;
    if (X.$async) H = G.scopeValue("Error", { ref: _A.default, code: X1._`require("ajv/dist/runtime/validation_error").default` });
    let B = G.scopeName("validate");
    X.validateName = B;
    let z = { gen: G, allErrors: this.opts.allErrors, data: B6.default.data, parentData: B6.default.parentData, parentDataProperty: B6.default.parentDataProperty, dataNames: [B6.default.data], dataPathArr: [X1.nil], dataLevel: 0, dataTypes: [], definedProperties: /* @__PURE__ */ new Set(), topSchemaRef: G.scopeValue("schema", this.opts.code.source === true ? { ref: X.schema, code: (0, X1.stringify)(X.schema) } : { ref: X.schema }), validateName: B, ValidationError: H, schema: X.schema, schemaEnv: X, rootId: $, baseId: X.baseId || $, schemaPath: X1.nil, errSchemaPath: X.schemaPath || (this.opts.jtd ? "" : "#"), errorPath: X1._`""`, opts: this.opts, self: this }, K;
    try {
      this._compilations.add(X), (0, xA.validateFunctionCode)(z), G.optimize(this.opts.code.optimize);
      let V = G.toString();
      if (K = `${G.scopeRefs(B6.default.scope)}return ${V}`, this.opts.code.process) K = this.opts.code.process(K, X);
      let U = Function(`${B6.default.self}`, `${B6.default.scope}`, K)(this, this.scope.get());
      if (this.scope.value(B, { ref: U }), U.errors = null, U.schema = X.schema, U.schemaEnv = X, X.$async) U.$async = true;
      if (this.opts.code.source === true) U.source = { validateName: B, validateCode: V, scopeValues: G._values };
      if (this.opts.unevaluated) {
        let { props: F, items: q } = z;
        if (U.evaluated = { props: F instanceof X1.Name ? void 0 : F, items: q instanceof X1.Name ? void 0 : q, dynamicProps: F instanceof X1.Name, dynamicItems: q instanceof X1.Name }, U.source) U.source.evaluated = (0, X1.stringify)(U.evaluated);
      }
      return X.validate = U, X;
    } catch (V) {
      if (delete X.validate, delete X.validateName, K) this.logger.error("Error compiling schema, function code:", K);
      throw V;
    } finally {
      this._compilations.delete(X);
    }
  }
  i3.compileSchema = bY;
  function yA(X, Q, $) {
    var Y;
    $ = (0, Q1.resolveUrl)(this.opts.uriResolver, Q, $);
    let W = X.refs[$];
    if (W) return W;
    let J = fA.call(this, X, $);
    if (J === void 0) {
      let G = (Y = X.localRefs) === null || Y === void 0 ? void 0 : Y[$], { schemaId: H } = this.opts;
      if (G) J = new rX({ schema: G, schemaId: H, root: X, baseId: Q });
    }
    if (J === void 0) return;
    return X.refs[$] = gA.call(this, J);
  }
  i3.resolveRef = yA;
  function gA(X) {
    if ((0, Q1.inlineRef)(X.schema, this.opts.inlineRefs)) return X.schema;
    return X.validate ? X : bY.call(this, X);
  }
  function d3(X) {
    for (let Q of this._compilations) if (hA(Q, X)) return Q;
  }
  i3.getCompilingSchema = d3;
  function hA(X, Q) {
    return X.schema === Q.schema && X.root === Q.root && X.baseId === Q.baseId;
  }
  function fA(X, Q) {
    let $;
    while (typeof ($ = this.refs[Q]) == "string") Q = $;
    return $ || this.schemas[Q] || T9.call(this, X, Q);
  }
  function T9(X, Q) {
    let $ = this.opts.uriResolver.parse(Q), Y = (0, Q1._getFullPath)(this.opts.uriResolver, $), W = (0, Q1.getFullPath)(this.opts.uriResolver, X.baseId, void 0);
    if (Object.keys(X.schema).length > 0 && Y === W) return IY.call(this, $, X);
    let J = (0, Q1.normalizeId)(Y), G = this.refs[J] || this.schemas[J];
    if (typeof G == "string") {
      let H = T9.call(this, X, G);
      if (typeof (H === null || H === void 0 ? void 0 : H.schema) !== "object") return;
      return IY.call(this, $, H);
    }
    if (typeof (G === null || G === void 0 ? void 0 : G.schema) !== "object") return;
    if (!G.validate) bY.call(this, G);
    if (J === (0, Q1.normalizeId)(Q)) {
      let { schema: H } = G, { schemaId: B } = this.opts, z = H[B];
      if (z) W = (0, Q1.resolveUrl)(this.opts.uriResolver, W, z);
      return new rX({ schema: H, schemaId: B, root: X, baseId: W });
    }
    return IY.call(this, $, G);
  }
  i3.resolveSchema = T9;
  var uA = /* @__PURE__ */ new Set(["properties", "patternProperties", "enum", "dependencies", "definitions"]);
  function IY(X, { baseId: Q, schema: $, root: Y }) {
    var W;
    if (((W = X.fragment) === null || W === void 0 ? void 0 : W[0]) !== "/") return;
    for (let H of X.fragment.slice(1).split("/")) {
      if (typeof $ === "boolean") return;
      let B = $[(0, p3.unescapeFragment)(H)];
      if (B === void 0) return;
      $ = B;
      let z = typeof $ === "object" && $[this.opts.schemaId];
      if (!uA.has(H) && z) Q = (0, Q1.resolveUrl)(this.opts.uriResolver, Q, z);
    }
    let J;
    if (typeof $ != "boolean" && $.$ref && !(0, p3.schemaHasRulesButRef)($, this.RULES)) {
      let H = (0, Q1.resolveUrl)(this.opts.uriResolver, Q, $.$ref);
      J = T9.call(this, Y, H);
    }
    let { schemaId: G } = this.opts;
    if (J = J || new rX({ schema: $, schemaId: G, root: Y, baseId: Q }), J.schema !== J.root.schema) return J;
    return;
  }
});
var r3 = P((ov, dA) => {
  dA.exports = { $id: "https://raw.githubusercontent.com/ajv-validator/ajv/master/lib/refs/data.json#", description: "Meta-schema for $data reference (JSON AnySchema extension proposal)", type: "object", required: ["$data"], properties: { $data: { type: "string", anyOf: [{ format: "relative-json-pointer" }, { format: "json-pointer" }] } }, additionalProperties: false };
});
var t3 = P((tv, o3) => {
  var iA = { 0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, a: 10, A: 10, b: 11, B: 11, c: 12, C: 12, d: 13, D: 13, e: 14, E: 14, f: 15, F: 15 };
  o3.exports = { HEX: iA };
});
var WH = P((av, YH) => {
  var { HEX: nA } = t3(), rA = /^(?:(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]\d|\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]\d|\d)$/u;
  function XH(X) {
    if ($H(X, ".") < 3) return { host: X, isIPV4: false };
    let Q = X.match(rA) || [], [$] = Q;
    if ($) return { host: tA($, "."), isIPV4: true };
    else return { host: X, isIPV4: false };
  }
  function PY(X, Q = false) {
    let $ = "", Y = true;
    for (let W of X) {
      if (nA[W] === void 0) return;
      if (W !== "0" && Y === true) Y = false;
      if (!Y) $ += W;
    }
    if (Q && $.length === 0) $ = "0";
    return $;
  }
  function oA(X) {
    let Q = 0, $ = { error: false, address: "", zone: "" }, Y = [], W = [], J = false, G = false, H = false;
    function B() {
      if (W.length) {
        if (J === false) {
          let z = PY(W);
          if (z !== void 0) Y.push(z);
          else return $.error = true, false;
        }
        W.length = 0;
      }
      return true;
    }
    for (let z = 0; z < X.length; z++) {
      let K = X[z];
      if (K === "[" || K === "]") continue;
      if (K === ":") {
        if (G === true) H = true;
        if (!B()) break;
        if (Q++, Y.push(":"), Q > 7) {
          $.error = true;
          break;
        }
        if (z - 1 >= 0 && X[z - 1] === ":") G = true;
        continue;
      } else if (K === "%") {
        if (!B()) break;
        J = true;
      } else {
        W.push(K);
        continue;
      }
    }
    if (W.length) if (J) $.zone = W.join("");
    else if (H) Y.push(W.join(""));
    else Y.push(PY(W));
    return $.address = Y.join(""), $;
  }
  function QH(X) {
    if ($H(X, ":") < 2) return { host: X, isIPV6: false };
    let Q = oA(X);
    if (!Q.error) {
      let { address: $, address: Y } = Q;
      if (Q.zone) $ += "%" + Q.zone, Y += "%25" + Q.zone;
      return { host: $, escapedHost: Y, isIPV6: true };
    } else return { host: X, isIPV6: false };
  }
  function tA(X, Q) {
    let $ = "", Y = true, W = X.length;
    for (let J = 0; J < W; J++) {
      let G = X[J];
      if (G === "0" && Y) {
        if (J + 1 <= W && X[J + 1] === Q || J + 1 === W) $ += G, Y = false;
      } else {
        if (G === Q) Y = true;
        else Y = false;
        $ += G;
      }
    }
    return $;
  }
  function $H(X, Q) {
    let $ = 0;
    for (let Y = 0; Y < X.length; Y++) if (X[Y] === Q) $++;
    return $;
  }
  var a3 = /^\.\.?\//u, s3 = /^\/\.(?:\/|$)/u, e3 = /^\/\.\.(?:\/|$)/u, aA = /^\/?(?:.|\n)*?(?=\/|$)/u;
  function sA(X) {
    let Q = [];
    while (X.length) if (X.match(a3)) X = X.replace(a3, "");
    else if (X.match(s3)) X = X.replace(s3, "/");
    else if (X.match(e3)) X = X.replace(e3, "/"), Q.pop();
    else if (X === "." || X === "..") X = "";
    else {
      let $ = X.match(aA);
      if ($) {
        let Y = $[0];
        X = X.slice(Y.length), Q.push(Y);
      } else throw Error("Unexpected dot segment condition");
    }
    return Q.join("");
  }
  function eA(X, Q) {
    let $ = Q !== true ? escape : unescape;
    if (X.scheme !== void 0) X.scheme = $(X.scheme);
    if (X.userinfo !== void 0) X.userinfo = $(X.userinfo);
    if (X.host !== void 0) X.host = $(X.host);
    if (X.path !== void 0) X.path = $(X.path);
    if (X.query !== void 0) X.query = $(X.query);
    if (X.fragment !== void 0) X.fragment = $(X.fragment);
    return X;
  }
  function Xw(X) {
    let Q = [];
    if (X.userinfo !== void 0) Q.push(X.userinfo), Q.push("@");
    if (X.host !== void 0) {
      let $ = unescape(X.host), Y = XH($);
      if (Y.isIPV4) $ = Y.host;
      else {
        let W = QH(Y.host);
        if (W.isIPV6 === true) $ = `[${W.escapedHost}]`;
        else $ = X.host;
      }
      Q.push($);
    }
    if (typeof X.port === "number" || typeof X.port === "string") Q.push(":"), Q.push(String(X.port));
    return Q.length ? Q.join("") : void 0;
  }
  YH.exports = { recomposeAuthority: Xw, normalizeComponentEncoding: eA, removeDotSegments: sA, normalizeIPv4: XH, normalizeIPv6: QH, stringArrayToHexStripped: PY };
});
var KH = P((sv, zH) => {
  var Qw = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/iu, $w = /([\da-z][\d\-a-z]{0,31}):((?:[\w!$'()*+,\-.:;=@]|%[\da-f]{2})+)/iu;
  function JH(X) {
    return typeof X.secure === "boolean" ? X.secure : String(X.scheme).toLowerCase() === "wss";
  }
  function GH(X) {
    if (!X.host) X.error = X.error || "HTTP URIs must have a host.";
    return X;
  }
  function HH(X) {
    let Q = String(X.scheme).toLowerCase() === "https";
    if (X.port === (Q ? 443 : 80) || X.port === "") X.port = void 0;
    if (!X.path) X.path = "/";
    return X;
  }
  function Yw(X) {
    return X.secure = JH(X), X.resourceName = (X.path || "/") + (X.query ? "?" + X.query : ""), X.path = void 0, X.query = void 0, X;
  }
  function Ww(X) {
    if (X.port === (JH(X) ? 443 : 80) || X.port === "") X.port = void 0;
    if (typeof X.secure === "boolean") X.scheme = X.secure ? "wss" : "ws", X.secure = void 0;
    if (X.resourceName) {
      let [Q, $] = X.resourceName.split("?");
      X.path = Q && Q !== "/" ? Q : void 0, X.query = $, X.resourceName = void 0;
    }
    return X.fragment = void 0, X;
  }
  function Jw(X, Q) {
    if (!X.path) return X.error = "URN can not be parsed", X;
    let $ = X.path.match($w);
    if ($) {
      let Y = Q.scheme || X.scheme || "urn";
      X.nid = $[1].toLowerCase(), X.nss = $[2];
      let W = `${Y}:${Q.nid || X.nid}`, J = SY[W];
      if (X.path = void 0, J) X = J.parse(X, Q);
    } else X.error = X.error || "URN can not be parsed.";
    return X;
  }
  function Gw(X, Q) {
    let $ = Q.scheme || X.scheme || "urn", Y = X.nid.toLowerCase(), W = `${$}:${Q.nid || Y}`, J = SY[W];
    if (J) X = J.serialize(X, Q);
    let G = X, H = X.nss;
    return G.path = `${Y || Q.nid}:${H}`, Q.skipEscape = true, G;
  }
  function Hw(X, Q) {
    let $ = X;
    if ($.uuid = $.nss, $.nss = void 0, !Q.tolerant && (!$.uuid || !Qw.test($.uuid))) $.error = $.error || "UUID is not valid.";
    return $;
  }
  function Bw(X) {
    let Q = X;
    return Q.nss = (X.uuid || "").toLowerCase(), Q;
  }
  var BH = { scheme: "http", domainHost: true, parse: GH, serialize: HH }, zw = { scheme: "https", domainHost: BH.domainHost, parse: GH, serialize: HH }, x9 = { scheme: "ws", domainHost: true, parse: Yw, serialize: Ww }, Kw = { scheme: "wss", domainHost: x9.domainHost, parse: x9.parse, serialize: x9.serialize }, Uw = { scheme: "urn", parse: Jw, serialize: Gw, skipNormalize: true }, Vw = { scheme: "urn:uuid", parse: Hw, serialize: Bw, skipNormalize: true }, SY = { http: BH, https: zw, ws: x9, wss: Kw, urn: Uw, "urn:uuid": Vw };
  zH.exports = SY;
});
var VH = P((ev, g9) => {
  var { normalizeIPv6: Lw, normalizeIPv4: qw, removeDotSegments: oX, recomposeAuthority: Fw, normalizeComponentEncoding: y9 } = WH(), ZY = KH();
  function Nw(X, Q) {
    if (typeof X === "string") X = V1(I1(X, Q), Q);
    else if (typeof X === "object") X = I1(V1(X, Q), Q);
    return X;
  }
  function Ow(X, Q, $) {
    let Y = Object.assign({ scheme: "null" }, $), W = UH(I1(X, Y), I1(Q, Y), Y, true);
    return V1(W, { ...Y, skipEscape: true });
  }
  function UH(X, Q, $, Y) {
    let W = {};
    if (!Y) X = I1(V1(X, $), $), Q = I1(V1(Q, $), $);
    if ($ = $ || {}, !$.tolerant && Q.scheme) W.scheme = Q.scheme, W.userinfo = Q.userinfo, W.host = Q.host, W.port = Q.port, W.path = oX(Q.path || ""), W.query = Q.query;
    else {
      if (Q.userinfo !== void 0 || Q.host !== void 0 || Q.port !== void 0) W.userinfo = Q.userinfo, W.host = Q.host, W.port = Q.port, W.path = oX(Q.path || ""), W.query = Q.query;
      else {
        if (!Q.path) if (W.path = X.path, Q.query !== void 0) W.query = Q.query;
        else W.query = X.query;
        else {
          if (Q.path.charAt(0) === "/") W.path = oX(Q.path);
          else {
            if ((X.userinfo !== void 0 || X.host !== void 0 || X.port !== void 0) && !X.path) W.path = "/" + Q.path;
            else if (!X.path) W.path = Q.path;
            else W.path = X.path.slice(0, X.path.lastIndexOf("/") + 1) + Q.path;
            W.path = oX(W.path);
          }
          W.query = Q.query;
        }
        W.userinfo = X.userinfo, W.host = X.host, W.port = X.port;
      }
      W.scheme = X.scheme;
    }
    return W.fragment = Q.fragment, W;
  }
  function Dw(X, Q, $) {
    if (typeof X === "string") X = unescape(X), X = V1(y9(I1(X, $), true), { ...$, skipEscape: true });
    else if (typeof X === "object") X = V1(y9(X, true), { ...$, skipEscape: true });
    if (typeof Q === "string") Q = unescape(Q), Q = V1(y9(I1(Q, $), true), { ...$, skipEscape: true });
    else if (typeof Q === "object") Q = V1(y9(Q, true), { ...$, skipEscape: true });
    return X.toLowerCase() === Q.toLowerCase();
  }
  function V1(X, Q) {
    let $ = { host: X.host, scheme: X.scheme, userinfo: X.userinfo, port: X.port, path: X.path, query: X.query, nid: X.nid, nss: X.nss, uuid: X.uuid, fragment: X.fragment, reference: X.reference, resourceName: X.resourceName, secure: X.secure, error: "" }, Y = Object.assign({}, Q), W = [], J = ZY[(Y.scheme || $.scheme || "").toLowerCase()];
    if (J && J.serialize) J.serialize($, Y);
    if ($.path !== void 0) if (!Y.skipEscape) {
      if ($.path = escape($.path), $.scheme !== void 0) $.path = $.path.split("%3A").join(":");
    } else $.path = unescape($.path);
    if (Y.reference !== "suffix" && $.scheme) W.push($.scheme, ":");
    let G = Fw($);
    if (G !== void 0) {
      if (Y.reference !== "suffix") W.push("//");
      if (W.push(G), $.path && $.path.charAt(0) !== "/") W.push("/");
    }
    if ($.path !== void 0) {
      let H = $.path;
      if (!Y.absolutePath && (!J || !J.absolutePath)) H = oX(H);
      if (G === void 0) H = H.replace(/^\/\//u, "/%2F");
      W.push(H);
    }
    if ($.query !== void 0) W.push("?", $.query);
    if ($.fragment !== void 0) W.push("#", $.fragment);
    return W.join("");
  }
  var Aw = Array.from({ length: 127 }, (X, Q) => /[^!"$&'()*+,\-.;=_`a-z{}~]/u.test(String.fromCharCode(Q)));
  function ww(X) {
    let Q = 0;
    for (let $ = 0, Y = X.length; $ < Y; ++$) if (Q = X.charCodeAt($), Q > 126 || Aw[Q]) return true;
    return false;
  }
  var Mw = /^(?:([^#/:?]+):)?(?:\/\/((?:([^#/?@]*)@)?(\[[^#/?\]]+\]|[^#/:?]*)(?::(\d*))?))?([^#?]*)(?:\?([^#]*))?(?:#((?:.|[\n\r])*))?/u;
  function I1(X, Q) {
    let $ = Object.assign({}, Q), Y = { scheme: void 0, userinfo: void 0, host: "", port: void 0, path: "", query: void 0, fragment: void 0 }, W = X.indexOf("%") !== -1, J = false;
    if ($.reference === "suffix") X = ($.scheme ? $.scheme + ":" : "") + "//" + X;
    let G = X.match(Mw);
    if (G) {
      if (Y.scheme = G[1], Y.userinfo = G[3], Y.host = G[4], Y.port = parseInt(G[5], 10), Y.path = G[6] || "", Y.query = G[7], Y.fragment = G[8], isNaN(Y.port)) Y.port = G[5];
      if (Y.host) {
        let B = qw(Y.host);
        if (B.isIPV4 === false) {
          let z = Lw(B.host);
          Y.host = z.host.toLowerCase(), J = z.isIPV6;
        } else Y.host = B.host, J = true;
      }
      if (Y.scheme === void 0 && Y.userinfo === void 0 && Y.host === void 0 && Y.port === void 0 && Y.query === void 0 && !Y.path) Y.reference = "same-document";
      else if (Y.scheme === void 0) Y.reference = "relative";
      else if (Y.fragment === void 0) Y.reference = "absolute";
      else Y.reference = "uri";
      if ($.reference && $.reference !== "suffix" && $.reference !== Y.reference) Y.error = Y.error || "URI is not a " + $.reference + " reference.";
      let H = ZY[($.scheme || Y.scheme || "").toLowerCase()];
      if (!$.unicodeSupport && (!H || !H.unicodeSupport)) {
        if (Y.host && ($.domainHost || H && H.domainHost) && J === false && ww(Y.host)) try {
          Y.host = URL.domainToASCII(Y.host.toLowerCase());
        } catch (B) {
          Y.error = Y.error || "Host's domain name can not be converted to ASCII: " + B;
        }
      }
      if (!H || H && !H.skipNormalize) {
        if (W && Y.scheme !== void 0) Y.scheme = unescape(Y.scheme);
        if (W && Y.host !== void 0) Y.host = unescape(Y.host);
        if (Y.path) Y.path = escape(unescape(Y.path));
        if (Y.fragment) Y.fragment = encodeURI(decodeURIComponent(Y.fragment));
      }
      if (H && H.parse) H.parse(Y, $);
    } else Y.error = Y.error || "URI can not be parsed.";
    return Y;
  }
  var CY = { SCHEMES: ZY, normalize: Nw, resolve: Ow, resolveComponents: UH, equal: Dw, serialize: V1, parse: I1 };
  g9.exports = CY;
  g9.exports.default = CY;
  g9.exports.fastUri = CY;
});
var FH = P((qH) => {
  Object.defineProperty(qH, "__esModule", { value: true });
  var LH = VH();
  LH.code = 'require("ajv/dist/runtime/uri").default';
  qH.default = LH;
});
var RH = P((b1) => {
  Object.defineProperty(b1, "__esModule", { value: true });
  b1.CodeGen = b1.Name = b1.nil = b1.stringify = b1.str = b1._ = b1.KeywordCxt = void 0;
  var Rw = iX();
  Object.defineProperty(b1, "KeywordCxt", { enumerable: true, get: function() {
    return Rw.KeywordCxt;
  } });
  var p6 = c();
  Object.defineProperty(b1, "_", { enumerable: true, get: function() {
    return p6._;
  } });
  Object.defineProperty(b1, "str", { enumerable: true, get: function() {
    return p6.str;
  } });
  Object.defineProperty(b1, "stringify", { enumerable: true, get: function() {
    return p6.stringify;
  } });
  Object.defineProperty(b1, "nil", { enumerable: true, get: function() {
    return p6.nil;
  } });
  Object.defineProperty(b1, "Name", { enumerable: true, get: function() {
    return p6.Name;
  } });
  Object.defineProperty(b1, "CodeGen", { enumerable: true, get: function() {
    return p6.CodeGen;
  } });
  var Ew = v9(), wH = nX(), Iw = KY(), tX = _9(), bw = c(), aX = cX(), h9 = mX(), vY = e(), NH = r3(), Pw = FH(), MH = (X, Q) => new RegExp(X, Q);
  MH.code = "new RegExp";
  var Sw = ["removeAdditional", "useDefaults", "coerceTypes"], Zw = /* @__PURE__ */ new Set(["validate", "serialize", "parse", "wrapper", "root", "schema", "keyword", "pattern", "formats", "validate$data", "func", "obj", "Error"]), Cw = { errorDataPath: "", format: "`validateFormats: false` can be used instead.", nullable: '"nullable" keyword is supported by default.', jsonPointers: "Deprecated jsPropertySyntax can be used instead.", extendRefs: "Deprecated ignoreKeywordsWithRef can be used instead.", missingRefs: "Pass empty schema with $id that should be ignored to ajv.addSchema.", processCode: "Use option `code: {process: (code, schemaEnv: object) => string}`", sourceCode: "Use option `code: {source: true}`", strictDefaults: "It is default now, see option `strict`.", strictKeywords: "It is default now, see option `strict`.", uniqueItems: '"uniqueItems" keyword is always validated.', unknownFormats: "Disable strict mode or pass `true` to `ajv.addFormat` (or `formats` option).", cache: "Map is used as cache, schema object as key.", serialize: "Map is used as cache, schema object as key.", ajvErrors: "It is default now." }, kw = { ignoreKeywordsWithRef: "", jsPropertySyntax: "", unicode: '"minLength"/"maxLength" account for unicode characters by default.' }, OH = 200;
  function vw(X) {
    var Q, $, Y, W, J, G, H, B, z, K, V, L, U, F, q, N, A, M, R, S, C, K0, U0, s, D0;
    let q0 = X.strict, W1 = (Q = X.code) === null || Q === void 0 ? void 0 : Q.optimize, P1 = W1 === true || W1 === void 0 ? 1 : W1 || 0, U6 = (Y = ($ = X.code) === null || $ === void 0 ? void 0 : $.regExp) !== null && Y !== void 0 ? Y : MH, d = (W = X.uriResolver) !== null && W !== void 0 ? W : Pw.default;
    return { strictSchema: (G = (J = X.strictSchema) !== null && J !== void 0 ? J : q0) !== null && G !== void 0 ? G : true, strictNumbers: (B = (H = X.strictNumbers) !== null && H !== void 0 ? H : q0) !== null && B !== void 0 ? B : true, strictTypes: (K = (z = X.strictTypes) !== null && z !== void 0 ? z : q0) !== null && K !== void 0 ? K : "log", strictTuples: (L = (V = X.strictTuples) !== null && V !== void 0 ? V : q0) !== null && L !== void 0 ? L : "log", strictRequired: (F = (U = X.strictRequired) !== null && U !== void 0 ? U : q0) !== null && F !== void 0 ? F : false, code: X.code ? { ...X.code, optimize: P1, regExp: U6 } : { optimize: P1, regExp: U6 }, loopRequired: (q = X.loopRequired) !== null && q !== void 0 ? q : OH, loopEnum: (N = X.loopEnum) !== null && N !== void 0 ? N : OH, meta: (A = X.meta) !== null && A !== void 0 ? A : true, messages: (M = X.messages) !== null && M !== void 0 ? M : true, inlineRefs: (R = X.inlineRefs) !== null && R !== void 0 ? R : true, schemaId: (S = X.schemaId) !== null && S !== void 0 ? S : "$id", addUsedSchema: (C = X.addUsedSchema) !== null && C !== void 0 ? C : true, validateSchema: (K0 = X.validateSchema) !== null && K0 !== void 0 ? K0 : true, validateFormats: (U0 = X.validateFormats) !== null && U0 !== void 0 ? U0 : true, unicodeRegExp: (s = X.unicodeRegExp) !== null && s !== void 0 ? s : true, int32range: (D0 = X.int32range) !== null && D0 !== void 0 ? D0 : true, uriResolver: d };
  }
  class f9 {
    constructor(X = {}) {
      this.schemas = {}, this.refs = {}, this.formats = {}, this._compilations = /* @__PURE__ */ new Set(), this._loading = {}, this._cache = /* @__PURE__ */ new Map(), X = this.opts = { ...X, ...vw(X) };
      let { es5: Q, lines: $ } = this.opts.code;
      this.scope = new bw.ValueScope({ scope: {}, prefixes: Zw, es5: Q, lines: $ }), this.logger = hw(X.logger);
      let Y = X.validateFormats;
      if (X.validateFormats = false, this.RULES = (0, Iw.getRules)(), DH.call(this, Cw, X, "NOT SUPPORTED"), DH.call(this, kw, X, "DEPRECATED", "warn"), this._metaOpts = yw.call(this), X.formats) _w.call(this);
      if (this._addVocabularies(), this._addDefaultMetaSchema(), X.keywords) xw.call(this, X.keywords);
      if (typeof X.meta == "object") this.addMetaSchema(X.meta);
      Tw.call(this), X.validateFormats = Y;
    }
    _addVocabularies() {
      this.addKeyword("$async");
    }
    _addDefaultMetaSchema() {
      let { $data: X, meta: Q, schemaId: $ } = this.opts, Y = NH;
      if ($ === "id") Y = { ...NH }, Y.id = Y.$id, delete Y.$id;
      if (Q && X) this.addMetaSchema(Y, Y[$], false);
    }
    defaultMeta() {
      let { meta: X, schemaId: Q } = this.opts;
      return this.opts.defaultMeta = typeof X == "object" ? X[Q] || X : void 0;
    }
    validate(X, Q) {
      let $;
      if (typeof X == "string") {
        if ($ = this.getSchema(X), !$) throw Error(`no schema with key or ref "${X}"`);
      } else $ = this.compile(X);
      let Y = $(Q);
      if (!("$async" in $)) this.errors = $.errors;
      return Y;
    }
    compile(X, Q) {
      let $ = this._addSchema(X, Q);
      return $.validate || this._compileSchemaEnv($);
    }
    compileAsync(X, Q) {
      if (typeof this.opts.loadSchema != "function") throw Error("options.loadSchema should be a function");
      let { loadSchema: $ } = this.opts;
      return Y.call(this, X, Q);
      async function Y(z, K) {
        await W.call(this, z.$schema);
        let V = this._addSchema(z, K);
        return V.validate || J.call(this, V);
      }
      async function W(z) {
        if (z && !this.getSchema(z)) await Y.call(this, { $ref: z }, true);
      }
      async function J(z) {
        try {
          return this._compileSchemaEnv(z);
        } catch (K) {
          if (!(K instanceof wH.default)) throw K;
          return G.call(this, K), await H.call(this, K.missingSchema), J.call(this, z);
        }
      }
      function G({ missingSchema: z, missingRef: K }) {
        if (this.refs[z]) throw Error(`AnySchema ${z} is loaded but ${K} cannot be resolved`);
      }
      async function H(z) {
        let K = await B.call(this, z);
        if (!this.refs[z]) await W.call(this, K.$schema);
        if (!this.refs[z]) this.addSchema(K, z, Q);
      }
      async function B(z) {
        let K = this._loading[z];
        if (K) return K;
        try {
          return await (this._loading[z] = $(z));
        } finally {
          delete this._loading[z];
        }
      }
    }
    addSchema(X, Q, $, Y = this.opts.validateSchema) {
      if (Array.isArray(X)) {
        for (let J of X) this.addSchema(J, void 0, $, Y);
        return this;
      }
      let W;
      if (typeof X === "object") {
        let { schemaId: J } = this.opts;
        if (W = X[J], W !== void 0 && typeof W != "string") throw Error(`schema ${J} must be string`);
      }
      return Q = (0, aX.normalizeId)(Q || W), this._checkUnique(Q), this.schemas[Q] = this._addSchema(X, $, Q, Y, true), this;
    }
    addMetaSchema(X, Q, $ = this.opts.validateSchema) {
      return this.addSchema(X, Q, true, $), this;
    }
    validateSchema(X, Q) {
      if (typeof X == "boolean") return true;
      let $;
      if ($ = X.$schema, $ !== void 0 && typeof $ != "string") throw Error("$schema must be a string");
      if ($ = $ || this.opts.defaultMeta || this.defaultMeta(), !$) return this.logger.warn("meta-schema not available"), this.errors = null, true;
      let Y = this.validate($, X);
      if (!Y && Q) {
        let W = "schema is invalid: " + this.errorsText();
        if (this.opts.validateSchema === "log") this.logger.error(W);
        else throw Error(W);
      }
      return Y;
    }
    getSchema(X) {
      let Q;
      while (typeof (Q = AH.call(this, X)) == "string") X = Q;
      if (Q === void 0) {
        let { schemaId: $ } = this.opts, Y = new tX.SchemaEnv({ schema: {}, schemaId: $ });
        if (Q = tX.resolveSchema.call(this, Y, X), !Q) return;
        this.refs[X] = Q;
      }
      return Q.validate || this._compileSchemaEnv(Q);
    }
    removeSchema(X) {
      if (X instanceof RegExp) return this._removeAllSchemas(this.schemas, X), this._removeAllSchemas(this.refs, X), this;
      switch (typeof X) {
        case "undefined":
          return this._removeAllSchemas(this.schemas), this._removeAllSchemas(this.refs), this._cache.clear(), this;
        case "string": {
          let Q = AH.call(this, X);
          if (typeof Q == "object") this._cache.delete(Q.schema);
          return delete this.schemas[X], delete this.refs[X], this;
        }
        case "object": {
          let Q = X;
          this._cache.delete(Q);
          let $ = X[this.opts.schemaId];
          if ($) $ = (0, aX.normalizeId)($), delete this.schemas[$], delete this.refs[$];
          return this;
        }
        default:
          throw Error("ajv.removeSchema: invalid parameter");
      }
    }
    addVocabulary(X) {
      for (let Q of X) this.addKeyword(Q);
      return this;
    }
    addKeyword(X, Q) {
      let $;
      if (typeof X == "string") {
        if ($ = X, typeof Q == "object") this.logger.warn("these parameters are deprecated, see docs for addKeyword"), Q.keyword = $;
      } else if (typeof X == "object" && Q === void 0) {
        if (Q = X, $ = Q.keyword, Array.isArray($) && !$.length) throw Error("addKeywords: keyword must be string or non-empty array");
      } else throw Error("invalid addKeywords parameters");
      if (uw.call(this, $, Q), !Q) return (0, vY.eachItem)($, (W) => kY.call(this, W)), this;
      mw.call(this, Q);
      let Y = { ...Q, type: (0, h9.getJSONTypes)(Q.type), schemaType: (0, h9.getJSONTypes)(Q.schemaType) };
      return (0, vY.eachItem)($, Y.type.length === 0 ? (W) => kY.call(this, W, Y) : (W) => Y.type.forEach((J) => kY.call(this, W, Y, J))), this;
    }
    getKeyword(X) {
      let Q = this.RULES.all[X];
      return typeof Q == "object" ? Q.definition : !!Q;
    }
    removeKeyword(X) {
      let { RULES: Q } = this;
      delete Q.keywords[X], delete Q.all[X];
      for (let $ of Q.rules) {
        let Y = $.rules.findIndex((W) => W.keyword === X);
        if (Y >= 0) $.rules.splice(Y, 1);
      }
      return this;
    }
    addFormat(X, Q) {
      if (typeof Q == "string") Q = new RegExp(Q);
      return this.formats[X] = Q, this;
    }
    errorsText(X = this.errors, { separator: Q = ", ", dataVar: $ = "data" } = {}) {
      if (!X || X.length === 0) return "No errors";
      return X.map((Y) => `${$}${Y.instancePath} ${Y.message}`).reduce((Y, W) => Y + Q + W);
    }
    $dataMetaSchema(X, Q) {
      let $ = this.RULES.all;
      X = JSON.parse(JSON.stringify(X));
      for (let Y of Q) {
        let W = Y.split("/").slice(1), J = X;
        for (let G of W) J = J[G];
        for (let G in $) {
          let H = $[G];
          if (typeof H != "object") continue;
          let { $data: B } = H.definition, z = J[G];
          if (B && z) J[G] = jH(z);
        }
      }
      return X;
    }
    _removeAllSchemas(X, Q) {
      for (let $ in X) {
        let Y = X[$];
        if (!Q || Q.test($)) {
          if (typeof Y == "string") delete X[$];
          else if (Y && !Y.meta) this._cache.delete(Y.schema), delete X[$];
        }
      }
    }
    _addSchema(X, Q, $, Y = this.opts.validateSchema, W = this.opts.addUsedSchema) {
      let J, { schemaId: G } = this.opts;
      if (typeof X == "object") J = X[G];
      else if (this.opts.jtd) throw Error("schema must be object");
      else if (typeof X != "boolean") throw Error("schema must be object or boolean");
      let H = this._cache.get(X);
      if (H !== void 0) return H;
      $ = (0, aX.normalizeId)(J || $);
      let B = aX.getSchemaRefs.call(this, X, $);
      if (H = new tX.SchemaEnv({ schema: X, schemaId: G, meta: Q, baseId: $, localRefs: B }), this._cache.set(H.schema, H), W && !$.startsWith("#")) {
        if ($) this._checkUnique($);
        this.refs[$] = H;
      }
      if (Y) this.validateSchema(X, true);
      return H;
    }
    _checkUnique(X) {
      if (this.schemas[X] || this.refs[X]) throw Error(`schema with key or id "${X}" already exists`);
    }
    _compileSchemaEnv(X) {
      if (X.meta) this._compileMetaSchema(X);
      else tX.compileSchema.call(this, X);
      if (!X.validate) throw Error("ajv implementation error");
      return X.validate;
    }
    _compileMetaSchema(X) {
      let Q = this.opts;
      this.opts = this._metaOpts;
      try {
        tX.compileSchema.call(this, X);
      } finally {
        this.opts = Q;
      }
    }
  }
  f9.ValidationError = Ew.default;
  f9.MissingRefError = wH.default;
  b1.default = f9;
  function DH(X, Q, $, Y = "error") {
    for (let W in X) {
      let J = W;
      if (J in Q) this.logger[Y](`${$}: option ${W}. ${X[J]}`);
    }
  }
  function AH(X) {
    return X = (0, aX.normalizeId)(X), this.schemas[X] || this.refs[X];
  }
  function Tw() {
    let X = this.opts.schemas;
    if (!X) return;
    if (Array.isArray(X)) this.addSchema(X);
    else for (let Q in X) this.addSchema(X[Q], Q);
  }
  function _w() {
    for (let X in this.opts.formats) {
      let Q = this.opts.formats[X];
      if (Q) this.addFormat(X, Q);
    }
  }
  function xw(X) {
    if (Array.isArray(X)) {
      this.addVocabulary(X);
      return;
    }
    this.logger.warn("keywords option as map is deprecated, pass array");
    for (let Q in X) {
      let $ = X[Q];
      if (!$.keyword) $.keyword = Q;
      this.addKeyword($);
    }
  }
  function yw() {
    let X = { ...this.opts };
    for (let Q of Sw) delete X[Q];
    return X;
  }
  var gw = { log() {
  }, warn() {
  }, error() {
  } };
  function hw(X) {
    if (X === false) return gw;
    if (X === void 0) return console;
    if (X.log && X.warn && X.error) return X;
    throw Error("logger must implement log, warn and error methods");
  }
  var fw = /^[a-z_$][a-z0-9_$:-]*$/i;
  function uw(X, Q) {
    let { RULES: $ } = this;
    if ((0, vY.eachItem)(X, (Y) => {
      if ($.keywords[Y]) throw Error(`Keyword ${Y} is already defined`);
      if (!fw.test(Y)) throw Error(`Keyword ${Y} has invalid name`);
    }), !Q) return;
    if (Q.$data && !("code" in Q || "validate" in Q)) throw Error('$data keyword must have "code" or "validate" function');
  }
  function kY(X, Q, $) {
    var Y;
    let W = Q === null || Q === void 0 ? void 0 : Q.post;
    if ($ && W) throw Error('keyword with "post" flag cannot have "type"');
    let { RULES: J } = this, G = W ? J.post : J.rules.find(({ type: B }) => B === $);
    if (!G) G = { type: $, rules: [] }, J.rules.push(G);
    if (J.keywords[X] = true, !Q) return;
    let H = { keyword: X, definition: { ...Q, type: (0, h9.getJSONTypes)(Q.type), schemaType: (0, h9.getJSONTypes)(Q.schemaType) } };
    if (Q.before) lw.call(this, G, H, Q.before);
    else G.rules.push(H);
    J.all[X] = H, (Y = Q.implements) === null || Y === void 0 || Y.forEach((B) => this.addKeyword(B));
  }
  function lw(X, Q, $) {
    let Y = X.rules.findIndex((W) => W.keyword === $);
    if (Y >= 0) X.rules.splice(Y, 0, Q);
    else X.rules.push(Q), this.logger.warn(`rule ${$} is not defined`);
  }
  function mw(X) {
    let { metaSchema: Q } = X;
    if (Q === void 0) return;
    if (X.$data && this.opts.$data) Q = jH(Q);
    X.validateSchema = this.compile(Q, true);
  }
  var cw = { $ref: "https://raw.githubusercontent.com/ajv-validator/ajv/master/lib/refs/data.json#" };
  function jH(X) {
    return { anyOf: [X, cw] };
  }
});
var IH = P((EH) => {
  Object.defineProperty(EH, "__esModule", { value: true });
  var iw = { keyword: "id", code() {
    throw Error('NOT SUPPORTED: keyword "id", use "$id" for schema ID');
  } };
  EH.default = iw;
});
var kH = P((ZH) => {
  Object.defineProperty(ZH, "__esModule", { value: true });
  ZH.callRef = ZH.getValidate = void 0;
  var rw = nX(), bH = d0(), g0 = c(), d6 = R1(), PH = _9(), u9 = e(), ow = { keyword: "$ref", schemaType: "string", code(X) {
    let { gen: Q, schema: $, it: Y } = X, { baseId: W, schemaEnv: J, validateName: G, opts: H, self: B } = Y, { root: z } = J;
    if (($ === "#" || $ === "#/") && W === z.baseId) return V();
    let K = PH.resolveRef.call(B, z, W, $);
    if (K === void 0) throw new rw.default(Y.opts.uriResolver, W, $);
    if (K instanceof PH.SchemaEnv) return L(K);
    return U(K);
    function V() {
      if (J === z) return l9(X, G, J, J.$async);
      let F = Q.scopeValue("root", { ref: z });
      return l9(X, g0._`${F}.validate`, z, z.$async);
    }
    function L(F) {
      let q = SH(X, F);
      l9(X, q, F, F.$async);
    }
    function U(F) {
      let q = Q.scopeValue("schema", H.code.source === true ? { ref: F, code: (0, g0.stringify)(F) } : { ref: F }), N = Q.name("valid"), A = X.subschema({ schema: F, dataTypes: [], schemaPath: g0.nil, topSchemaRef: q, errSchemaPath: $ }, N);
      X.mergeEvaluated(A), X.ok(N);
    }
  } };
  function SH(X, Q) {
    let { gen: $ } = X;
    return Q.validate ? $.scopeValue("validate", { ref: Q.validate }) : g0._`${$.scopeValue("wrapper", { ref: Q })}.validate`;
  }
  ZH.getValidate = SH;
  function l9(X, Q, $, Y) {
    let { gen: W, it: J } = X, { allErrors: G, schemaEnv: H, opts: B } = J, z = B.passContext ? d6.default.this : g0.nil;
    if (Y) K();
    else V();
    function K() {
      if (!H.$async) throw Error("async schema referenced by sync schema");
      let F = W.let("valid");
      W.try(() => {
        if (W.code(g0._`await ${(0, bH.callValidateCode)(X, Q, z)}`), U(Q), !G) W.assign(F, true);
      }, (q) => {
        if (W.if(g0._`!(${q} instanceof ${J.ValidationError})`, () => W.throw(q)), L(q), !G) W.assign(F, false);
      }), X.ok(F);
    }
    function V() {
      X.result((0, bH.callValidateCode)(X, Q, z), () => U(Q), () => L(Q));
    }
    function L(F) {
      let q = g0._`${F}.errors`;
      W.assign(d6.default.vErrors, g0._`${d6.default.vErrors} === null ? ${q} : ${d6.default.vErrors}.concat(${q})`), W.assign(d6.default.errors, g0._`${d6.default.vErrors}.length`);
    }
    function U(F) {
      var q;
      if (!J.opts.unevaluated) return;
      let N = (q = $ === null || $ === void 0 ? void 0 : $.validate) === null || q === void 0 ? void 0 : q.evaluated;
      if (J.props !== true) if (N && !N.dynamicProps) {
        if (N.props !== void 0) J.props = u9.mergeEvaluated.props(W, N.props, J.props);
      } else {
        let A = W.var("props", g0._`${F}.evaluated.props`);
        J.props = u9.mergeEvaluated.props(W, A, J.props, g0.Name);
      }
      if (J.items !== true) if (N && !N.dynamicItems) {
        if (N.items !== void 0) J.items = u9.mergeEvaluated.items(W, N.items, J.items);
      } else {
        let A = W.var("items", g0._`${F}.evaluated.items`);
        J.items = u9.mergeEvaluated.items(W, A, J.items, g0.Name);
      }
    }
  }
  ZH.callRef = l9;
  ZH.default = ow;
});
var TH = P((vH) => {
  Object.defineProperty(vH, "__esModule", { value: true });
  var sw = IH(), ew = kH(), XM = ["$schema", "$id", "$defs", "$vocabulary", { keyword: "$comment" }, "definitions", sw.default, ew.default];
  vH.default = XM;
});
var xH = P((_H) => {
  Object.defineProperty(_H, "__esModule", { value: true });
  var m9 = c(), d1 = m9.operators, c9 = { maximum: { okStr: "<=", ok: d1.LTE, fail: d1.GT }, minimum: { okStr: ">=", ok: d1.GTE, fail: d1.LT }, exclusiveMaximum: { okStr: "<", ok: d1.LT, fail: d1.GTE }, exclusiveMinimum: { okStr: ">", ok: d1.GT, fail: d1.LTE } }, $M = { message: ({ keyword: X, schemaCode: Q }) => m9.str`must be ${c9[X].okStr} ${Q}`, params: ({ keyword: X, schemaCode: Q }) => m9._`{comparison: ${c9[X].okStr}, limit: ${Q}}` }, YM = { keyword: Object.keys(c9), type: "number", schemaType: "number", $data: true, error: $M, code(X) {
    let { keyword: Q, data: $, schemaCode: Y } = X;
    X.fail$data(m9._`${$} ${c9[Q].fail} ${Y} || isNaN(${$})`);
  } };
  _H.default = YM;
});
var gH = P((yH) => {
  Object.defineProperty(yH, "__esModule", { value: true });
  var sX = c(), JM = { message: ({ schemaCode: X }) => sX.str`must be multiple of ${X}`, params: ({ schemaCode: X }) => sX._`{multipleOf: ${X}}` }, GM = { keyword: "multipleOf", type: "number", schemaType: "number", $data: true, error: JM, code(X) {
    let { gen: Q, data: $, schemaCode: Y, it: W } = X, J = W.opts.multipleOfPrecision, G = Q.let("res"), H = J ? sX._`Math.abs(Math.round(${G}) - ${G}) > 1e-${J}` : sX._`${G} !== parseInt(${G})`;
    X.fail$data(sX._`(${Y} === 0 || (${G} = ${$}/${Y}, ${H}))`);
  } };
  yH.default = GM;
});
var uH = P((fH) => {
  Object.defineProperty(fH, "__esModule", { value: true });
  function hH(X) {
    let Q = X.length, $ = 0, Y = 0, W;
    while (Y < Q) if ($++, W = X.charCodeAt(Y++), W >= 55296 && W <= 56319 && Y < Q) {
      if (W = X.charCodeAt(Y), (W & 64512) === 56320) Y++;
    }
    return $;
  }
  fH.default = hH;
  hH.code = 'require("ajv/dist/runtime/ucs2length").default';
});
var mH = P((lH) => {
  Object.defineProperty(lH, "__esModule", { value: true });
  var z6 = c(), zM = e(), KM = uH(), UM = { message({ keyword: X, schemaCode: Q }) {
    let $ = X === "maxLength" ? "more" : "fewer";
    return z6.str`must NOT have ${$} than ${Q} characters`;
  }, params: ({ schemaCode: X }) => z6._`{limit: ${X}}` }, VM = { keyword: ["maxLength", "minLength"], type: "string", schemaType: "number", $data: true, error: UM, code(X) {
    let { keyword: Q, data: $, schemaCode: Y, it: W } = X, J = Q === "maxLength" ? z6.operators.GT : z6.operators.LT, G = W.opts.unicode === false ? z6._`${$}.length` : z6._`${(0, zM.useFunc)(X.gen, KM.default)}(${$})`;
    X.fail$data(z6._`${G} ${J} ${Y}`);
  } };
  lH.default = VM;
});
var pH = P((cH) => {
  Object.defineProperty(cH, "__esModule", { value: true });
  var qM = d0(), p9 = c(), FM = { message: ({ schemaCode: X }) => p9.str`must match pattern "${X}"`, params: ({ schemaCode: X }) => p9._`{pattern: ${X}}` }, NM = { keyword: "pattern", type: "string", schemaType: "string", $data: true, error: FM, code(X) {
    let { data: Q, $data: $, schema: Y, schemaCode: W, it: J } = X, G = J.opts.unicodeRegExp ? "u" : "", H = $ ? p9._`(new RegExp(${W}, ${G}))` : (0, qM.usePattern)(X, Y);
    X.fail$data(p9._`!${H}.test(${Q})`);
  } };
  cH.default = NM;
});
var iH = P((dH) => {
  Object.defineProperty(dH, "__esModule", { value: true });
  var eX = c(), DM = { message({ keyword: X, schemaCode: Q }) {
    let $ = X === "maxProperties" ? "more" : "fewer";
    return eX.str`must NOT have ${$} than ${Q} properties`;
  }, params: ({ schemaCode: X }) => eX._`{limit: ${X}}` }, AM = { keyword: ["maxProperties", "minProperties"], type: "object", schemaType: "number", $data: true, error: DM, code(X) {
    let { keyword: Q, data: $, schemaCode: Y } = X, W = Q === "maxProperties" ? eX.operators.GT : eX.operators.LT;
    X.fail$data(eX._`Object.keys(${$}).length ${W} ${Y}`);
  } };
  dH.default = AM;
});
var rH = P((nH) => {
  Object.defineProperty(nH, "__esModule", { value: true });
  var X4 = d0(), Q4 = c(), MM = e(), jM = { message: ({ params: { missingProperty: X } }) => Q4.str`must have required property '${X}'`, params: ({ params: { missingProperty: X } }) => Q4._`{missingProperty: ${X}}` }, RM = { keyword: "required", type: "object", schemaType: "array", $data: true, error: jM, code(X) {
    let { gen: Q, schema: $, schemaCode: Y, data: W, $data: J, it: G } = X, { opts: H } = G;
    if (!J && $.length === 0) return;
    let B = $.length >= H.loopRequired;
    if (G.allErrors) z();
    else K();
    if (H.strictRequired) {
      let U = X.parentSchema.properties, { definedProperties: F } = X.it;
      for (let q of $) if ((U === null || U === void 0 ? void 0 : U[q]) === void 0 && !F.has(q)) {
        let N = G.schemaEnv.baseId + G.errSchemaPath, A = `required property "${q}" is not defined at "${N}" (strictRequired)`;
        (0, MM.checkStrictMode)(G, A, G.opts.strictRequired);
      }
    }
    function z() {
      if (B || J) X.block$data(Q4.nil, V);
      else for (let U of $) (0, X4.checkReportMissingProp)(X, U);
    }
    function K() {
      let U = Q.let("missing");
      if (B || J) {
        let F = Q.let("valid", true);
        X.block$data(F, () => L(U, F)), X.ok(F);
      } else Q.if((0, X4.checkMissingProp)(X, $, U)), (0, X4.reportMissingProp)(X, U), Q.else();
    }
    function V() {
      Q.forOf("prop", Y, (U) => {
        X.setParams({ missingProperty: U }), Q.if((0, X4.noPropertyInData)(Q, W, U, H.ownProperties), () => X.error());
      });
    }
    function L(U, F) {
      X.setParams({ missingProperty: U }), Q.forOf(U, Y, () => {
        Q.assign(F, (0, X4.propertyInData)(Q, W, U, H.ownProperties)), Q.if((0, Q4.not)(F), () => {
          X.error(), Q.break();
        });
      }, Q4.nil);
    }
  } };
  nH.default = RM;
});
var tH = P((oH) => {
  Object.defineProperty(oH, "__esModule", { value: true });
  var $4 = c(), IM = { message({ keyword: X, schemaCode: Q }) {
    let $ = X === "maxItems" ? "more" : "fewer";
    return $4.str`must NOT have ${$} than ${Q} items`;
  }, params: ({ schemaCode: X }) => $4._`{limit: ${X}}` }, bM = { keyword: ["maxItems", "minItems"], type: "array", schemaType: "number", $data: true, error: IM, code(X) {
    let { keyword: Q, data: $, schemaCode: Y } = X, W = Q === "maxItems" ? $4.operators.GT : $4.operators.LT;
    X.fail$data($4._`${$}.length ${W} ${Y}`);
  } };
  oH.default = bM;
});
var d9 = P((sH) => {
  Object.defineProperty(sH, "__esModule", { value: true });
  var aH = DY();
  aH.code = 'require("ajv/dist/runtime/equal").default';
  sH.default = aH;
});
var XB = P((eH) => {
  Object.defineProperty(eH, "__esModule", { value: true });
  var TY = mX(), E0 = c(), ZM = e(), CM = d9(), kM = { message: ({ params: { i: X, j: Q } }) => E0.str`must NOT have duplicate items (items ## ${Q} and ${X} are identical)`, params: ({ params: { i: X, j: Q } }) => E0._`{i: ${X}, j: ${Q}}` }, vM = { keyword: "uniqueItems", type: "array", schemaType: "boolean", $data: true, error: kM, code(X) {
    let { gen: Q, data: $, $data: Y, schema: W, parentSchema: J, schemaCode: G, it: H } = X;
    if (!Y && !W) return;
    let B = Q.let("valid"), z = J.items ? (0, TY.getSchemaTypes)(J.items) : [];
    X.block$data(B, K, E0._`${G} === false`), X.ok(B);
    function K() {
      let F = Q.let("i", E0._`${$}.length`), q = Q.let("j");
      X.setParams({ i: F, j: q }), Q.assign(B, true), Q.if(E0._`${F} > 1`, () => (V() ? L : U)(F, q));
    }
    function V() {
      return z.length > 0 && !z.some((F) => F === "object" || F === "array");
    }
    function L(F, q) {
      let N = Q.name("item"), A = (0, TY.checkDataTypes)(z, N, H.opts.strictNumbers, TY.DataType.Wrong), M = Q.const("indices", E0._`{}`);
      Q.for(E0._`;${F}--;`, () => {
        if (Q.let(N, E0._`${$}[${F}]`), Q.if(A, E0._`continue`), z.length > 1) Q.if(E0._`typeof ${N} == "string"`, E0._`${N} += "_"`);
        Q.if(E0._`typeof ${M}[${N}] == "number"`, () => {
          Q.assign(q, E0._`${M}[${N}]`), X.error(), Q.assign(B, false).break();
        }).code(E0._`${M}[${N}] = ${F}`);
      });
    }
    function U(F, q) {
      let N = (0, ZM.useFunc)(Q, CM.default), A = Q.name("outer");
      Q.label(A).for(E0._`;${F}--;`, () => Q.for(E0._`${q} = ${F}; ${q}--;`, () => Q.if(E0._`${N}(${$}[${F}], ${$}[${q}])`, () => {
        X.error(), Q.assign(B, false).break(A);
      })));
    }
  } };
  eH.default = vM;
});
var $B = P((QB) => {
  Object.defineProperty(QB, "__esModule", { value: true });
  var _Y = c(), _M = e(), xM = d9(), yM = { message: "must be equal to constant", params: ({ schemaCode: X }) => _Y._`{allowedValue: ${X}}` }, gM = { keyword: "const", $data: true, error: yM, code(X) {
    let { gen: Q, data: $, $data: Y, schemaCode: W, schema: J } = X;
    if (Y || J && typeof J == "object") X.fail$data(_Y._`!${(0, _M.useFunc)(Q, xM.default)}(${$}, ${W})`);
    else X.fail(_Y._`${J} !== ${$}`);
  } };
  QB.default = gM;
});
var WB = P((YB) => {
  Object.defineProperty(YB, "__esModule", { value: true });
  var Y4 = c(), fM = e(), uM = d9(), lM = { message: "must be equal to one of the allowed values", params: ({ schemaCode: X }) => Y4._`{allowedValues: ${X}}` }, mM = { keyword: "enum", schemaType: "array", $data: true, error: lM, code(X) {
    let { gen: Q, data: $, $data: Y, schema: W, schemaCode: J, it: G } = X;
    if (!Y && W.length === 0) throw Error("enum must have non-empty array");
    let H = W.length >= G.opts.loopEnum, B, z = () => B !== null && B !== void 0 ? B : B = (0, fM.useFunc)(Q, uM.default), K;
    if (H || Y) K = Q.let("valid"), X.block$data(K, V);
    else {
      if (!Array.isArray(W)) throw Error("ajv implementation error");
      let U = Q.const("vSchema", J);
      K = (0, Y4.or)(...W.map((F, q) => L(U, q)));
    }
    X.pass(K);
    function V() {
      Q.assign(K, false), Q.forOf("v", J, (U) => Q.if(Y4._`${z()}(${$}, ${U})`, () => Q.assign(K, true).break()));
    }
    function L(U, F) {
      let q = W[F];
      return typeof q === "object" && q !== null ? Y4._`${z()}(${$}, ${U}[${F}])` : Y4._`${$} === ${q}`;
    }
  } };
  YB.default = mM;
});
var GB = P((JB) => {
  Object.defineProperty(JB, "__esModule", { value: true });
  var pM = xH(), dM = gH(), iM = mH(), nM = pH(), rM = iH(), oM = rH(), tM = tH(), aM = XB(), sM = $B(), eM = WB(), Xj = [pM.default, dM.default, iM.default, nM.default, rM.default, oM.default, tM.default, aM.default, { keyword: "type", schemaType: ["string", "array"] }, { keyword: "nullable", schemaType: "boolean" }, sM.default, eM.default];
  JB.default = Xj;
});
var yY = P((BB) => {
  Object.defineProperty(BB, "__esModule", { value: true });
  BB.validateAdditionalItems = void 0;
  var K6 = c(), xY = e(), $j = { message: ({ params: { len: X } }) => K6.str`must NOT have more than ${X} items`, params: ({ params: { len: X } }) => K6._`{limit: ${X}}` }, Yj = { keyword: "additionalItems", type: "array", schemaType: ["boolean", "object"], before: "uniqueItems", error: $j, code(X) {
    let { parentSchema: Q, it: $ } = X, { items: Y } = Q;
    if (!Array.isArray(Y)) {
      (0, xY.checkStrictMode)($, '"additionalItems" is ignored when "items" is not an array of schemas');
      return;
    }
    HB(X, Y);
  } };
  function HB(X, Q) {
    let { gen: $, schema: Y, data: W, keyword: J, it: G } = X;
    G.items = true;
    let H = $.const("len", K6._`${W}.length`);
    if (Y === false) X.setParams({ len: Q.length }), X.pass(K6._`${H} <= ${Q.length}`);
    else if (typeof Y == "object" && !(0, xY.alwaysValidSchema)(G, Y)) {
      let z = $.var("valid", K6._`${H} <= ${Q.length}`);
      $.if((0, K6.not)(z), () => B(z)), X.ok(z);
    }
    function B(z) {
      $.forRange("i", Q.length, H, (K) => {
        if (X.subschema({ keyword: J, dataProp: K, dataPropType: xY.Type.Num }, z), !G.allErrors) $.if((0, K6.not)(z), () => $.break());
      });
    }
  }
  BB.validateAdditionalItems = HB;
  BB.default = Yj;
});
var gY = P((VB) => {
  Object.defineProperty(VB, "__esModule", { value: true });
  VB.validateTuple = void 0;
  var KB = c(), i9 = e(), Jj = d0(), Gj = { keyword: "items", type: "array", schemaType: ["object", "array", "boolean"], before: "uniqueItems", code(X) {
    let { schema: Q, it: $ } = X;
    if (Array.isArray(Q)) return UB(X, "additionalItems", Q);
    if ($.items = true, (0, i9.alwaysValidSchema)($, Q)) return;
    X.ok((0, Jj.validateArray)(X));
  } };
  function UB(X, Q, $ = X.schema) {
    let { gen: Y, parentSchema: W, data: J, keyword: G, it: H } = X;
    if (K(W), H.opts.unevaluated && $.length && H.items !== true) H.items = i9.mergeEvaluated.items(Y, $.length, H.items);
    let B = Y.name("valid"), z = Y.const("len", KB._`${J}.length`);
    $.forEach((V, L) => {
      if ((0, i9.alwaysValidSchema)(H, V)) return;
      Y.if(KB._`${z} > ${L}`, () => X.subschema({ keyword: G, schemaProp: L, dataProp: L }, B)), X.ok(B);
    });
    function K(V) {
      let { opts: L, errSchemaPath: U } = H, F = $.length, q = F === V.minItems && (F === V.maxItems || V[Q] === false);
      if (L.strictTuples && !q) {
        let N = `"${G}" is ${F}-tuple, but minItems or maxItems/${Q} are not specified or different at path "${U}"`;
        (0, i9.checkStrictMode)(H, N, L.strictTuples);
      }
    }
  }
  VB.validateTuple = UB;
  VB.default = Gj;
});
var FB = P((qB) => {
  Object.defineProperty(qB, "__esModule", { value: true });
  var Bj = gY(), zj = { keyword: "prefixItems", type: "array", schemaType: ["array"], before: "uniqueItems", code: (X) => (0, Bj.validateTuple)(X, "items") };
  qB.default = zj;
});
var DB = P((OB) => {
  Object.defineProperty(OB, "__esModule", { value: true });
  var NB = c(), Uj = e(), Vj = d0(), Lj = yY(), qj = { message: ({ params: { len: X } }) => NB.str`must NOT have more than ${X} items`, params: ({ params: { len: X } }) => NB._`{limit: ${X}}` }, Fj = { keyword: "items", type: "array", schemaType: ["object", "boolean"], before: "uniqueItems", error: qj, code(X) {
    let { schema: Q, parentSchema: $, it: Y } = X, { prefixItems: W } = $;
    if (Y.items = true, (0, Uj.alwaysValidSchema)(Y, Q)) return;
    if (W) (0, Lj.validateAdditionalItems)(X, W);
    else X.ok((0, Vj.validateArray)(X));
  } };
  OB.default = Fj;
});
var wB = P((AB) => {
  Object.defineProperty(AB, "__esModule", { value: true });
  var i0 = c(), n9 = e(), Oj = { message: ({ params: { min: X, max: Q } }) => Q === void 0 ? i0.str`must contain at least ${X} valid item(s)` : i0.str`must contain at least ${X} and no more than ${Q} valid item(s)`, params: ({ params: { min: X, max: Q } }) => Q === void 0 ? i0._`{minContains: ${X}}` : i0._`{minContains: ${X}, maxContains: ${Q}}` }, Dj = { keyword: "contains", type: "array", schemaType: ["object", "boolean"], before: "uniqueItems", trackErrors: true, error: Oj, code(X) {
    let { gen: Q, schema: $, parentSchema: Y, data: W, it: J } = X, G, H, { minContains: B, maxContains: z } = Y;
    if (J.opts.next) G = B === void 0 ? 1 : B, H = z;
    else G = 1;
    let K = Q.const("len", i0._`${W}.length`);
    if (X.setParams({ min: G, max: H }), H === void 0 && G === 0) {
      (0, n9.checkStrictMode)(J, '"minContains" == 0 without "maxContains": "contains" keyword ignored');
      return;
    }
    if (H !== void 0 && G > H) {
      (0, n9.checkStrictMode)(J, '"minContains" > "maxContains" is always invalid'), X.fail();
      return;
    }
    if ((0, n9.alwaysValidSchema)(J, $)) {
      let q = i0._`${K} >= ${G}`;
      if (H !== void 0) q = i0._`${q} && ${K} <= ${H}`;
      X.pass(q);
      return;
    }
    J.items = true;
    let V = Q.name("valid");
    if (H === void 0 && G === 1) U(V, () => Q.if(V, () => Q.break()));
    else if (G === 0) {
      if (Q.let(V, true), H !== void 0) Q.if(i0._`${W}.length > 0`, L);
    } else Q.let(V, false), L();
    X.result(V, () => X.reset());
    function L() {
      let q = Q.name("_valid"), N = Q.let("count", 0);
      U(q, () => Q.if(q, () => F(N)));
    }
    function U(q, N) {
      Q.forRange("i", 0, K, (A) => {
        X.subschema({ keyword: "contains", dataProp: A, dataPropType: n9.Type.Num, compositeRule: true }, q), N();
      });
    }
    function F(q) {
      if (Q.code(i0._`${q}++`), H === void 0) Q.if(i0._`${q} >= ${G}`, () => Q.assign(V, true).break());
      else if (Q.if(i0._`${q} > ${H}`, () => Q.assign(V, false).break()), G === 1) Q.assign(V, true);
      else Q.if(i0._`${q} >= ${G}`, () => Q.assign(V, true));
    }
  } };
  AB.default = Dj;
});
var bB = P((RB) => {
  Object.defineProperty(RB, "__esModule", { value: true });
  RB.validateSchemaDeps = RB.validatePropertyDeps = RB.error = void 0;
  var hY = c(), wj = e(), W4 = d0();
  RB.error = { message: ({ params: { property: X, depsCount: Q, deps: $ } }) => {
    let Y = Q === 1 ? "property" : "properties";
    return hY.str`must have ${Y} ${$} when property ${X} is present`;
  }, params: ({ params: { property: X, depsCount: Q, deps: $, missingProperty: Y } }) => hY._`{property: ${X},
    missingProperty: ${Y},
    depsCount: ${Q},
    deps: ${$}}` };
  var Mj = { keyword: "dependencies", type: "object", schemaType: "object", error: RB.error, code(X) {
    let [Q, $] = jj(X);
    MB(X, Q), jB(X, $);
  } };
  function jj({ schema: X }) {
    let Q = {}, $ = {};
    for (let Y in X) {
      if (Y === "__proto__") continue;
      let W = Array.isArray(X[Y]) ? Q : $;
      W[Y] = X[Y];
    }
    return [Q, $];
  }
  function MB(X, Q = X.schema) {
    let { gen: $, data: Y, it: W } = X;
    if (Object.keys(Q).length === 0) return;
    let J = $.let("missing");
    for (let G in Q) {
      let H = Q[G];
      if (H.length === 0) continue;
      let B = (0, W4.propertyInData)($, Y, G, W.opts.ownProperties);
      if (X.setParams({ property: G, depsCount: H.length, deps: H.join(", ") }), W.allErrors) $.if(B, () => {
        for (let z of H) (0, W4.checkReportMissingProp)(X, z);
      });
      else $.if(hY._`${B} && (${(0, W4.checkMissingProp)(X, H, J)})`), (0, W4.reportMissingProp)(X, J), $.else();
    }
  }
  RB.validatePropertyDeps = MB;
  function jB(X, Q = X.schema) {
    let { gen: $, data: Y, keyword: W, it: J } = X, G = $.name("valid");
    for (let H in Q) {
      if ((0, wj.alwaysValidSchema)(J, Q[H])) continue;
      $.if((0, W4.propertyInData)($, Y, H, J.opts.ownProperties), () => {
        let B = X.subschema({ keyword: W, schemaProp: H }, G);
        X.mergeValidEvaluated(B, G);
      }, () => $.var(G, true)), X.ok(G);
    }
  }
  RB.validateSchemaDeps = jB;
  RB.default = Mj;
});
var ZB = P((SB) => {
  Object.defineProperty(SB, "__esModule", { value: true });
  var PB = c(), Ij = e(), bj = { message: "property name must be valid", params: ({ params: X }) => PB._`{propertyName: ${X.propertyName}}` }, Pj = { keyword: "propertyNames", type: "object", schemaType: ["object", "boolean"], error: bj, code(X) {
    let { gen: Q, schema: $, data: Y, it: W } = X;
    if ((0, Ij.alwaysValidSchema)(W, $)) return;
    let J = Q.name("valid");
    Q.forIn("key", Y, (G) => {
      X.setParams({ propertyName: G }), X.subschema({ keyword: "propertyNames", data: G, dataTypes: ["string"], propertyName: G, compositeRule: true }, J), Q.if((0, PB.not)(J), () => {
        if (X.error(true), !W.allErrors) Q.break();
      });
    }), X.ok(J);
  } };
  SB.default = Pj;
});
var fY = P((CB) => {
  Object.defineProperty(CB, "__esModule", { value: true });
  var r9 = d0(), $1 = c(), Zj = R1(), o9 = e(), Cj = { message: "must NOT have additional properties", params: ({ params: X }) => $1._`{additionalProperty: ${X.additionalProperty}}` }, kj = { keyword: "additionalProperties", type: ["object"], schemaType: ["boolean", "object"], allowUndefined: true, trackErrors: true, error: Cj, code(X) {
    let { gen: Q, schema: $, parentSchema: Y, data: W, errsCount: J, it: G } = X;
    if (!J) throw Error("ajv implementation error");
    let { allErrors: H, opts: B } = G;
    if (G.props = true, B.removeAdditional !== "all" && (0, o9.alwaysValidSchema)(G, $)) return;
    let z = (0, r9.allSchemaProperties)(Y.properties), K = (0, r9.allSchemaProperties)(Y.patternProperties);
    V(), X.ok($1._`${J} === ${Zj.default.errors}`);
    function V() {
      Q.forIn("key", W, (N) => {
        if (!z.length && !K.length) F(N);
        else Q.if(L(N), () => F(N));
      });
    }
    function L(N) {
      let A;
      if (z.length > 8) {
        let M = (0, o9.schemaRefOrVal)(G, Y.properties, "properties");
        A = (0, r9.isOwnProperty)(Q, M, N);
      } else if (z.length) A = (0, $1.or)(...z.map((M) => $1._`${N} === ${M}`));
      else A = $1.nil;
      if (K.length) A = (0, $1.or)(A, ...K.map((M) => $1._`${(0, r9.usePattern)(X, M)}.test(${N})`));
      return (0, $1.not)(A);
    }
    function U(N) {
      Q.code($1._`delete ${W}[${N}]`);
    }
    function F(N) {
      if (B.removeAdditional === "all" || B.removeAdditional && $ === false) {
        U(N);
        return;
      }
      if ($ === false) {
        if (X.setParams({ additionalProperty: N }), X.error(), !H) Q.break();
        return;
      }
      if (typeof $ == "object" && !(0, o9.alwaysValidSchema)(G, $)) {
        let A = Q.name("valid");
        if (B.removeAdditional === "failing") q(N, A, false), Q.if((0, $1.not)(A), () => {
          X.reset(), U(N);
        });
        else if (q(N, A), !H) Q.if((0, $1.not)(A), () => Q.break());
      }
    }
    function q(N, A, M) {
      let R = { keyword: "additionalProperties", dataProp: N, dataPropType: o9.Type.Str };
      if (M === false) Object.assign(R, { compositeRule: true, createErrors: false, allErrors: false });
      X.subschema(R, A);
    }
  } };
  CB.default = kj;
});
var _B = P((TB) => {
  Object.defineProperty(TB, "__esModule", { value: true });
  var Tj = iX(), kB = d0(), uY = e(), vB = fY(), _j = { keyword: "properties", type: "object", schemaType: "object", code(X) {
    let { gen: Q, schema: $, parentSchema: Y, data: W, it: J } = X;
    if (J.opts.removeAdditional === "all" && Y.additionalProperties === void 0) vB.default.code(new Tj.KeywordCxt(J, vB.default, "additionalProperties"));
    let G = (0, kB.allSchemaProperties)($);
    for (let V of G) J.definedProperties.add(V);
    if (J.opts.unevaluated && G.length && J.props !== true) J.props = uY.mergeEvaluated.props(Q, (0, uY.toHash)(G), J.props);
    let H = G.filter((V) => !(0, uY.alwaysValidSchema)(J, $[V]));
    if (H.length === 0) return;
    let B = Q.name("valid");
    for (let V of H) {
      if (z(V)) K(V);
      else {
        if (Q.if((0, kB.propertyInData)(Q, W, V, J.opts.ownProperties)), K(V), !J.allErrors) Q.else().var(B, true);
        Q.endIf();
      }
      X.it.definedProperties.add(V), X.ok(B);
    }
    function z(V) {
      return J.opts.useDefaults && !J.compositeRule && $[V].default !== void 0;
    }
    function K(V) {
      X.subschema({ keyword: "properties", schemaProp: V, dataProp: V }, B);
    }
  } };
  TB.default = _j;
});
var fB = P((hB) => {
  Object.defineProperty(hB, "__esModule", { value: true });
  var xB = d0(), t9 = c(), yB = e(), gB = e(), yj = { keyword: "patternProperties", type: "object", schemaType: "object", code(X) {
    let { gen: Q, schema: $, data: Y, parentSchema: W, it: J } = X, { opts: G } = J, H = (0, xB.allSchemaProperties)($), B = H.filter((q) => (0, yB.alwaysValidSchema)(J, $[q]));
    if (H.length === 0 || B.length === H.length && (!J.opts.unevaluated || J.props === true)) return;
    let z = G.strictSchema && !G.allowMatchingProperties && W.properties, K = Q.name("valid");
    if (J.props !== true && !(J.props instanceof t9.Name)) J.props = (0, gB.evaluatedPropsToName)(Q, J.props);
    let { props: V } = J;
    L();
    function L() {
      for (let q of H) {
        if (z) U(q);
        if (J.allErrors) F(q);
        else Q.var(K, true), F(q), Q.if(K);
      }
    }
    function U(q) {
      for (let N in z) if (new RegExp(q).test(N)) (0, yB.checkStrictMode)(J, `property ${N} matches pattern ${q} (use allowMatchingProperties)`);
    }
    function F(q) {
      Q.forIn("key", Y, (N) => {
        Q.if(t9._`${(0, xB.usePattern)(X, q)}.test(${N})`, () => {
          let A = B.includes(q);
          if (!A) X.subschema({ keyword: "patternProperties", schemaProp: q, dataProp: N, dataPropType: gB.Type.Str }, K);
          if (J.opts.unevaluated && V !== true) Q.assign(t9._`${V}[${N}]`, true);
          else if (!A && !J.allErrors) Q.if((0, t9.not)(K), () => Q.break());
        });
      });
    }
  } };
  hB.default = yj;
});
var lB = P((uB) => {
  Object.defineProperty(uB, "__esModule", { value: true });
  var hj = e(), fj = { keyword: "not", schemaType: ["object", "boolean"], trackErrors: true, code(X) {
    let { gen: Q, schema: $, it: Y } = X;
    if ((0, hj.alwaysValidSchema)(Y, $)) {
      X.fail();
      return;
    }
    let W = Q.name("valid");
    X.subschema({ keyword: "not", compositeRule: true, createErrors: false, allErrors: false }, W), X.failResult(W, () => X.reset(), () => X.error());
  }, error: { message: "must NOT be valid" } };
  uB.default = fj;
});
var cB = P((mB) => {
  Object.defineProperty(mB, "__esModule", { value: true });
  var lj = d0(), mj = { keyword: "anyOf", schemaType: "array", trackErrors: true, code: lj.validateUnion, error: { message: "must match a schema in anyOf" } };
  mB.default = mj;
});
var dB = P((pB) => {
  Object.defineProperty(pB, "__esModule", { value: true });
  var a9 = c(), pj = e(), dj = { message: "must match exactly one schema in oneOf", params: ({ params: X }) => a9._`{passingSchemas: ${X.passing}}` }, ij = { keyword: "oneOf", schemaType: "array", trackErrors: true, error: dj, code(X) {
    let { gen: Q, schema: $, parentSchema: Y, it: W } = X;
    if (!Array.isArray($)) throw Error("ajv implementation error");
    if (W.opts.discriminator && Y.discriminator) return;
    let J = $, G = Q.let("valid", false), H = Q.let("passing", null), B = Q.name("_valid");
    X.setParams({ passing: H }), Q.block(z), X.result(G, () => X.reset(), () => X.error(true));
    function z() {
      J.forEach((K, V) => {
        let L;
        if ((0, pj.alwaysValidSchema)(W, K)) Q.var(B, true);
        else L = X.subschema({ keyword: "oneOf", schemaProp: V, compositeRule: true }, B);
        if (V > 0) Q.if(a9._`${B} && ${G}`).assign(G, false).assign(H, a9._`[${H}, ${V}]`).else();
        Q.if(B, () => {
          if (Q.assign(G, true), Q.assign(H, V), L) X.mergeEvaluated(L, a9.Name);
        });
      });
    }
  } };
  pB.default = ij;
});
var nB = P((iB) => {
  Object.defineProperty(iB, "__esModule", { value: true });
  var rj = e(), oj = { keyword: "allOf", schemaType: "array", code(X) {
    let { gen: Q, schema: $, it: Y } = X;
    if (!Array.isArray($)) throw Error("ajv implementation error");
    let W = Q.name("valid");
    $.forEach((J, G) => {
      if ((0, rj.alwaysValidSchema)(Y, J)) return;
      let H = X.subschema({ keyword: "allOf", schemaProp: G }, W);
      X.ok(W), X.mergeEvaluated(H);
    });
  } };
  iB.default = oj;
});
var aB = P((tB) => {
  Object.defineProperty(tB, "__esModule", { value: true });
  var s9 = c(), oB = e(), aj = { message: ({ params: X }) => s9.str`must match "${X.ifClause}" schema`, params: ({ params: X }) => s9._`{failingKeyword: ${X.ifClause}}` }, sj = { keyword: "if", schemaType: ["object", "boolean"], trackErrors: true, error: aj, code(X) {
    let { gen: Q, parentSchema: $, it: Y } = X;
    if ($.then === void 0 && $.else === void 0) (0, oB.checkStrictMode)(Y, '"if" without "then" and "else" is ignored');
    let W = rB(Y, "then"), J = rB(Y, "else");
    if (!W && !J) return;
    let G = Q.let("valid", true), H = Q.name("_valid");
    if (B(), X.reset(), W && J) {
      let K = Q.let("ifClause");
      X.setParams({ ifClause: K }), Q.if(H, z("then", K), z("else", K));
    } else if (W) Q.if(H, z("then"));
    else Q.if((0, s9.not)(H), z("else"));
    X.pass(G, () => X.error(true));
    function B() {
      let K = X.subschema({ keyword: "if", compositeRule: true, createErrors: false, allErrors: false }, H);
      X.mergeEvaluated(K);
    }
    function z(K, V) {
      return () => {
        let L = X.subschema({ keyword: K }, H);
        if (Q.assign(G, H), X.mergeValidEvaluated(L, G), V) Q.assign(V, s9._`${K}`);
        else X.setParams({ ifClause: K });
      };
    }
  } };
  function rB(X, Q) {
    let $ = X.schema[Q];
    return $ !== void 0 && !(0, oB.alwaysValidSchema)(X, $);
  }
  tB.default = sj;
});
var eB = P((sB) => {
  Object.defineProperty(sB, "__esModule", { value: true });
  var XR = e(), QR = { keyword: ["then", "else"], schemaType: ["object", "boolean"], code({ keyword: X, parentSchema: Q, it: $ }) {
    if (Q.if === void 0) (0, XR.checkStrictMode)($, `"${X}" without "if" is ignored`);
  } };
  sB.default = QR;
});
var Qz = P((Xz) => {
  Object.defineProperty(Xz, "__esModule", { value: true });
  var YR = yY(), WR = FB(), JR = gY(), GR = DB(), HR = wB(), BR = bB(), zR = ZB(), KR = fY(), UR = _B(), VR = fB(), LR = lB(), qR = cB(), FR = dB(), NR = nB(), OR = aB(), DR = eB();
  function AR(X = false) {
    let Q = [LR.default, qR.default, FR.default, NR.default, OR.default, DR.default, zR.default, KR.default, BR.default, UR.default, VR.default];
    if (X) Q.push(WR.default, GR.default);
    else Q.push(YR.default, JR.default);
    return Q.push(HR.default), Q;
  }
  Xz.default = AR;
});
var Yz = P(($z) => {
  Object.defineProperty($z, "__esModule", { value: true });
  var L0 = c(), MR = { message: ({ schemaCode: X }) => L0.str`must match format "${X}"`, params: ({ schemaCode: X }) => L0._`{format: ${X}}` }, jR = { keyword: "format", type: ["number", "string"], schemaType: "string", $data: true, error: MR, code(X, Q) {
    let { gen: $, data: Y, $data: W, schema: J, schemaCode: G, it: H } = X, { opts: B, errSchemaPath: z, schemaEnv: K, self: V } = H;
    if (!B.validateFormats) return;
    if (W) L();
    else U();
    function L() {
      let F = $.scopeValue("formats", { ref: V.formats, code: B.code.formats }), q = $.const("fDef", L0._`${F}[${G}]`), N = $.let("fType"), A = $.let("format");
      $.if(L0._`typeof ${q} == "object" && !(${q} instanceof RegExp)`, () => $.assign(N, L0._`${q}.type || "string"`).assign(A, L0._`${q}.validate`), () => $.assign(N, L0._`"string"`).assign(A, q)), X.fail$data((0, L0.or)(M(), R()));
      function M() {
        if (B.strictSchema === false) return L0.nil;
        return L0._`${G} && !${A}`;
      }
      function R() {
        let S = K.$async ? L0._`(${q}.async ? await ${A}(${Y}) : ${A}(${Y}))` : L0._`${A}(${Y})`, C = L0._`(typeof ${A} == "function" ? ${S} : ${A}.test(${Y}))`;
        return L0._`${A} && ${A} !== true && ${N} === ${Q} && !${C}`;
      }
    }
    function U() {
      let F = V.formats[J];
      if (!F) {
        M();
        return;
      }
      if (F === true) return;
      let [q, N, A] = R(F);
      if (q === Q) X.pass(S());
      function M() {
        if (B.strictSchema === false) {
          V.logger.warn(C());
          return;
        }
        throw Error(C());
        function C() {
          return `unknown format "${J}" ignored in schema at path "${z}"`;
        }
      }
      function R(C) {
        let K0 = C instanceof RegExp ? (0, L0.regexpCode)(C) : B.code.formats ? L0._`${B.code.formats}${(0, L0.getProperty)(J)}` : void 0, U0 = $.scopeValue("formats", { key: J, ref: C, code: K0 });
        if (typeof C == "object" && !(C instanceof RegExp)) return [C.type || "string", C.validate, L0._`${U0}.validate`];
        return ["string", C, U0];
      }
      function S() {
        if (typeof F == "object" && !(F instanceof RegExp) && F.async) {
          if (!K.$async) throw Error("async format in sync schema");
          return L0._`await ${A}(${Y})`;
        }
        return typeof N == "function" ? L0._`${A}(${Y})` : L0._`${A}.test(${Y})`;
      }
    }
  } };
  $z.default = jR;
});
var Jz = P((Wz) => {
  Object.defineProperty(Wz, "__esModule", { value: true });
  var ER = Yz(), IR = [ER.default];
  Wz.default = IR;
});
var Bz = P((Gz) => {
  Object.defineProperty(Gz, "__esModule", { value: true });
  Gz.contentVocabulary = Gz.metadataVocabulary = void 0;
  Gz.metadataVocabulary = ["title", "description", "default", "deprecated", "readOnly", "writeOnly", "examples"];
  Gz.contentVocabulary = ["contentMediaType", "contentEncoding", "contentSchema"];
});
var Uz = P((Kz) => {
  Object.defineProperty(Kz, "__esModule", { value: true });
  var SR = TH(), ZR = GB(), CR = Qz(), kR = Jz(), zz = Bz(), vR = [SR.default, ZR.default, (0, CR.default)(), kR.default, zz.metadataVocabulary, zz.contentVocabulary];
  Kz.default = vR;
});
var Fz = P((Lz) => {
  Object.defineProperty(Lz, "__esModule", { value: true });
  Lz.DiscrError = void 0;
  var Vz;
  (function(X) {
    X.Tag = "tag", X.Mapping = "mapping";
  })(Vz || (Lz.DiscrError = Vz = {}));
});
var Dz = P((Oz) => {
  Object.defineProperty(Oz, "__esModule", { value: true });
  var i6 = c(), lY = Fz(), Nz = _9(), _R = nX(), xR = e(), yR = { message: ({ params: { discrError: X, tagName: Q } }) => X === lY.DiscrError.Tag ? `tag "${Q}" must be string` : `value of tag "${Q}" must be in oneOf`, params: ({ params: { discrError: X, tag: Q, tagName: $ } }) => i6._`{error: ${X}, tag: ${$}, tagValue: ${Q}}` }, gR = { keyword: "discriminator", type: "object", schemaType: "object", error: yR, code(X) {
    let { gen: Q, data: $, schema: Y, parentSchema: W, it: J } = X, { oneOf: G } = W;
    if (!J.opts.discriminator) throw Error("discriminator: requires discriminator option");
    let H = Y.propertyName;
    if (typeof H != "string") throw Error("discriminator: requires propertyName");
    if (Y.mapping) throw Error("discriminator: mapping is not supported");
    if (!G) throw Error("discriminator: requires oneOf keyword");
    let B = Q.let("valid", false), z = Q.const("tag", i6._`${$}${(0, i6.getProperty)(H)}`);
    Q.if(i6._`typeof ${z} == "string"`, () => K(), () => X.error(false, { discrError: lY.DiscrError.Tag, tag: z, tagName: H })), X.ok(B);
    function K() {
      let U = L();
      Q.if(false);
      for (let F in U) Q.elseIf(i6._`${z} === ${F}`), Q.assign(B, V(U[F]));
      Q.else(), X.error(false, { discrError: lY.DiscrError.Mapping, tag: z, tagName: H }), Q.endIf();
    }
    function V(U) {
      let F = Q.name("valid"), q = X.subschema({ keyword: "oneOf", schemaProp: U }, F);
      return X.mergeEvaluated(q, i6.Name), F;
    }
    function L() {
      var U;
      let F = {}, q = A(W), N = true;
      for (let S = 0; S < G.length; S++) {
        let C = G[S];
        if ((C === null || C === void 0 ? void 0 : C.$ref) && !(0, xR.schemaHasRulesButRef)(C, J.self.RULES)) {
          let U0 = C.$ref;
          if (C = Nz.resolveRef.call(J.self, J.schemaEnv.root, J.baseId, U0), C instanceof Nz.SchemaEnv) C = C.schema;
          if (C === void 0) throw new _R.default(J.opts.uriResolver, J.baseId, U0);
        }
        let K0 = (U = C === null || C === void 0 ? void 0 : C.properties) === null || U === void 0 ? void 0 : U[H];
        if (typeof K0 != "object") throw Error(`discriminator: oneOf subschemas (or referenced schemas) must have "properties/${H}"`);
        N = N && (q || A(C)), M(K0, S);
      }
      if (!N) throw Error(`discriminator: "${H}" must be required`);
      return F;
      function A({ required: S }) {
        return Array.isArray(S) && S.includes(H);
      }
      function M(S, C) {
        if (S.const) R(S.const, C);
        else if (S.enum) for (let K0 of S.enum) R(K0, C);
        else throw Error(`discriminator: "properties/${H}" must have "const" or "enum"`);
      }
      function R(S, C) {
        if (typeof S != "string" || S in F) throw Error(`discriminator: "${H}" values must be unique strings`);
        F[S] = C;
      }
    }
  } };
  Oz.default = gR;
});
var Az = P((nT, fR) => {
  fR.exports = { $schema: "http://json-schema.org/draft-07/schema#", $id: "http://json-schema.org/draft-07/schema#", title: "Core schema meta-schema", definitions: { schemaArray: { type: "array", minItems: 1, items: { $ref: "#" } }, nonNegativeInteger: { type: "integer", minimum: 0 }, nonNegativeIntegerDefault0: { allOf: [{ $ref: "#/definitions/nonNegativeInteger" }, { default: 0 }] }, simpleTypes: { enum: ["array", "boolean", "integer", "null", "number", "object", "string"] }, stringArray: { type: "array", items: { type: "string" }, uniqueItems: true, default: [] } }, type: ["object", "boolean"], properties: { $id: { type: "string", format: "uri-reference" }, $schema: { type: "string", format: "uri" }, $ref: { type: "string", format: "uri-reference" }, $comment: { type: "string" }, title: { type: "string" }, description: { type: "string" }, default: true, readOnly: { type: "boolean", default: false }, examples: { type: "array", items: true }, multipleOf: { type: "number", exclusiveMinimum: 0 }, maximum: { type: "number" }, exclusiveMaximum: { type: "number" }, minimum: { type: "number" }, exclusiveMinimum: { type: "number" }, maxLength: { $ref: "#/definitions/nonNegativeInteger" }, minLength: { $ref: "#/definitions/nonNegativeIntegerDefault0" }, pattern: { type: "string", format: "regex" }, additionalItems: { $ref: "#" }, items: { anyOf: [{ $ref: "#" }, { $ref: "#/definitions/schemaArray" }], default: true }, maxItems: { $ref: "#/definitions/nonNegativeInteger" }, minItems: { $ref: "#/definitions/nonNegativeIntegerDefault0" }, uniqueItems: { type: "boolean", default: false }, contains: { $ref: "#" }, maxProperties: { $ref: "#/definitions/nonNegativeInteger" }, minProperties: { $ref: "#/definitions/nonNegativeIntegerDefault0" }, required: { $ref: "#/definitions/stringArray" }, additionalProperties: { $ref: "#" }, definitions: { type: "object", additionalProperties: { $ref: "#" }, default: {} }, properties: { type: "object", additionalProperties: { $ref: "#" }, default: {} }, patternProperties: { type: "object", additionalProperties: { $ref: "#" }, propertyNames: { format: "regex" }, default: {} }, dependencies: { type: "object", additionalProperties: { anyOf: [{ $ref: "#" }, { $ref: "#/definitions/stringArray" }] } }, propertyNames: { $ref: "#" }, const: true, enum: { type: "array", items: true, minItems: 1, uniqueItems: true }, type: { anyOf: [{ $ref: "#/definitions/simpleTypes" }, { type: "array", items: { $ref: "#/definitions/simpleTypes" }, minItems: 1, uniqueItems: true }] }, format: { type: "string" }, contentMediaType: { type: "string" }, contentEncoding: { type: "string" }, if: { $ref: "#" }, then: { $ref: "#" }, else: { $ref: "#" }, allOf: { $ref: "#/definitions/schemaArray" }, anyOf: { $ref: "#/definitions/schemaArray" }, oneOf: { $ref: "#/definitions/schemaArray" }, not: { $ref: "#" } }, default: true };
});
var cY = P((h0, mY) => {
  Object.defineProperty(h0, "__esModule", { value: true });
  h0.MissingRefError = h0.ValidationError = h0.CodeGen = h0.Name = h0.nil = h0.stringify = h0.str = h0._ = h0.KeywordCxt = h0.Ajv = void 0;
  var uR = RH(), lR = Uz(), mR = Dz(), wz = Az(), cR = ["/properties"], e9 = "http://json-schema.org/draft-07/schema";
  class J4 extends uR.default {
    _addVocabularies() {
      if (super._addVocabularies(), lR.default.forEach((X) => this.addVocabulary(X)), this.opts.discriminator) this.addKeyword(mR.default);
    }
    _addDefaultMetaSchema() {
      if (super._addDefaultMetaSchema(), !this.opts.meta) return;
      let X = this.opts.$data ? this.$dataMetaSchema(wz, cR) : wz;
      this.addMetaSchema(X, e9, false), this.refs["http://json-schema.org/schema"] = e9;
    }
    defaultMeta() {
      return this.opts.defaultMeta = super.defaultMeta() || (this.getSchema(e9) ? e9 : void 0);
    }
  }
  h0.Ajv = J4;
  mY.exports = h0 = J4;
  mY.exports.Ajv = J4;
  Object.defineProperty(h0, "__esModule", { value: true });
  h0.default = J4;
  var pR = iX();
  Object.defineProperty(h0, "KeywordCxt", { enumerable: true, get: function() {
    return pR.KeywordCxt;
  } });
  var n6 = c();
  Object.defineProperty(h0, "_", { enumerable: true, get: function() {
    return n6._;
  } });
  Object.defineProperty(h0, "str", { enumerable: true, get: function() {
    return n6.str;
  } });
  Object.defineProperty(h0, "stringify", { enumerable: true, get: function() {
    return n6.stringify;
  } });
  Object.defineProperty(h0, "nil", { enumerable: true, get: function() {
    return n6.nil;
  } });
  Object.defineProperty(h0, "Name", { enumerable: true, get: function() {
    return n6.Name;
  } });
  Object.defineProperty(h0, "CodeGen", { enumerable: true, get: function() {
    return n6.CodeGen;
  } });
  var dR = v9();
  Object.defineProperty(h0, "ValidationError", { enumerable: true, get: function() {
    return dR.default;
  } });
  var iR = nX();
  Object.defineProperty(h0, "MissingRefError", { enumerable: true, get: function() {
    return iR.default;
  } });
});
var Cz = P((Sz) => {
  Object.defineProperty(Sz, "__esModule", { value: true });
  Sz.formatNames = Sz.fastFormats = Sz.fullFormats = void 0;
  function L1(X, Q) {
    return { validate: X, compare: Q };
  }
  Sz.fullFormats = { date: L1(Ez, nY), time: L1(dY(true), rY), "date-time": L1(Mz(true), bz), "iso-time": L1(dY(), Iz), "iso-date-time": L1(Mz(), Pz), duration: /^P(?!$)((\d+Y)?(\d+M)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+S)?)?|(\d+W)?)$/, uri: XE, "uri-reference": /^(?:[a-z][a-z0-9+\-.]*:)?(?:\/?\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\[(?:(?:(?:(?:[0-9a-f]{1,4}:){6}|::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:){0,1}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4})?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4})?::)|[Vv][0-9a-f]+\.[a-z0-9\-._~!$&'()*+,;=:]+)\]|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)|(?:[a-z0-9\-._~!$&'"()*+,;=]|%[0-9a-f]{2})*)(?::\d*)?(?:\/(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})*)*|\/(?:(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})*)*)?(?:\?(?:[a-z0-9\-._~!$&'"()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[a-z0-9\-._~!$&'"()*+,;=:@/?]|%[0-9a-f]{2})*)?$/i, "uri-template": /^(?:(?:[^\x00-\x20"'<>%\\^`{|}]|%[0-9a-f]{2})|\{[+#./;?&=,!@|]?(?:[a-z0-9_]|%[0-9a-f]{2})+(?::[1-9][0-9]{0,3}|\*)?(?:,(?:[a-z0-9_]|%[0-9a-f]{2})+(?::[1-9][0-9]{0,3}|\*)?)*\})*$/i, url: /^(?:https?|ftp):\/\/(?:\S+(?::\S*)?@)?(?:(?!(?:10|127)(?:\.\d{1,3}){3})(?!(?:169\.254|192\.168)(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z0-9\u{00a1}-\u{ffff}]+-)*[a-z0-9\u{00a1}-\u{ffff}]+)(?:\.(?:[a-z0-9\u{00a1}-\u{ffff}]+-)*[a-z0-9\u{00a1}-\u{ffff}]+)*(?:\.(?:[a-z\u{00a1}-\u{ffff}]{2,})))(?::\d{2,5})?(?:\/[^\s]*)?$/iu, email: /^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i, hostname: /^(?=.{1,253}\.?$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[-0-9a-z]{0,61}[0-9a-z])?)*\.?$/i, ipv4: /^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$/, ipv6: /^((([0-9a-f]{1,4}:){7}([0-9a-f]{1,4}|:))|(([0-9a-f]{1,4}:){6}(:[0-9a-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9a-f]{1,4}:){5}(((:[0-9a-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9a-f]{1,4}:){4}(((:[0-9a-f]{1,4}){1,3})|((:[0-9a-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){3}(((:[0-9a-f]{1,4}){1,4})|((:[0-9a-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){2}(((:[0-9a-f]{1,4}){1,5})|((:[0-9a-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){1}(((:[0-9a-f]{1,4}){1,6})|((:[0-9a-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9a-f]{1,4}){1,7})|((:[0-9a-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))$/i, regex: HE, uuid: /^(?:urn:uuid:)?[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i, "json-pointer": /^(?:\/(?:[^~/]|~0|~1)*)*$/, "json-pointer-uri-fragment": /^#(?:\/(?:[a-z0-9_\-.!$&'()*+,;:=@]|%[0-9a-f]{2}|~0|~1)*)*$/i, "relative-json-pointer": /^(?:0|[1-9][0-9]*)(?:#|(?:\/(?:[^~/]|~0|~1)*)*)$/, byte: QE, int32: { type: "number", validate: WE }, int64: { type: "number", validate: JE }, float: { type: "number", validate: Rz }, double: { type: "number", validate: Rz }, password: true, binary: true };
  Sz.fastFormats = { ...Sz.fullFormats, date: L1(/^\d\d\d\d-[0-1]\d-[0-3]\d$/, nY), time: L1(/^(?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)$/i, rY), "date-time": L1(/^\d\d\d\d-[0-1]\d-[0-3]\dt(?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)$/i, bz), "iso-time": L1(/^(?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)?$/i, Iz), "iso-date-time": L1(/^\d\d\d\d-[0-1]\d-[0-3]\d[t\s](?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)?$/i, Pz), uri: /^(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/)?[^\s]*$/i, "uri-reference": /^(?:(?:[a-z][a-z0-9+\-.]*:)?\/?\/)?(?:[^\\\s#][^\s#]*)?(?:#[^\\\s]*)?$/i, email: /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$/i };
  Sz.formatNames = Object.keys(Sz.fullFormats);
  function oR(X) {
    return X % 4 === 0 && (X % 100 !== 0 || X % 400 === 0);
  }
  var tR = /^(\d\d\d\d)-(\d\d)-(\d\d)$/, aR = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  function Ez(X) {
    let Q = tR.exec(X);
    if (!Q) return false;
    let $ = +Q[1], Y = +Q[2], W = +Q[3];
    return Y >= 1 && Y <= 12 && W >= 1 && W <= (Y === 2 && oR($) ? 29 : aR[Y]);
  }
  function nY(X, Q) {
    if (!(X && Q)) return;
    if (X > Q) return 1;
    if (X < Q) return -1;
    return 0;
  }
  var pY = /^(\d\d):(\d\d):(\d\d(?:\.\d+)?)(z|([+-])(\d\d)(?::?(\d\d))?)?$/i;
  function dY(X) {
    return function($) {
      let Y = pY.exec($);
      if (!Y) return false;
      let W = +Y[1], J = +Y[2], G = +Y[3], H = Y[4], B = Y[5] === "-" ? -1 : 1, z = +(Y[6] || 0), K = +(Y[7] || 0);
      if (z > 23 || K > 59 || X && !H) return false;
      if (W <= 23 && J <= 59 && G < 60) return true;
      let V = J - K * B, L = W - z * B - (V < 0 ? 1 : 0);
      return (L === 23 || L === -1) && (V === 59 || V === -1) && G < 61;
    };
  }
  function rY(X, Q) {
    if (!(X && Q)) return;
    let $ = (/* @__PURE__ */ new Date("2020-01-01T" + X)).valueOf(), Y = (/* @__PURE__ */ new Date("2020-01-01T" + Q)).valueOf();
    if (!($ && Y)) return;
    return $ - Y;
  }
  function Iz(X, Q) {
    if (!(X && Q)) return;
    let $ = pY.exec(X), Y = pY.exec(Q);
    if (!($ && Y)) return;
    if (X = $[1] + $[2] + $[3], Q = Y[1] + Y[2] + Y[3], X > Q) return 1;
    if (X < Q) return -1;
    return 0;
  }
  var iY = /t|\s/i;
  function Mz(X) {
    let Q = dY(X);
    return function(Y) {
      let W = Y.split(iY);
      return W.length === 2 && Ez(W[0]) && Q(W[1]);
    };
  }
  function bz(X, Q) {
    if (!(X && Q)) return;
    let $ = new Date(X).valueOf(), Y = new Date(Q).valueOf();
    if (!($ && Y)) return;
    return $ - Y;
  }
  function Pz(X, Q) {
    if (!(X && Q)) return;
    let [$, Y] = X.split(iY), [W, J] = Q.split(iY), G = nY($, W);
    if (G === void 0) return;
    return G || rY(Y, J);
  }
  var sR = /\/|:/, eR = /^(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\[(?:(?:(?:(?:[0-9a-f]{1,4}:){6}|::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:){0,1}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4})?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4})?::)|[Vv][0-9a-f]+\.[a-z0-9\-._~!$&'()*+,;=:]+)\]|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)|(?:[a-z0-9\-._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\d*)?(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*|\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)(?:\?(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?$/i;
  function XE(X) {
    return sR.test(X) && eR.test(X);
  }
  var jz = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/gm;
  function QE(X) {
    return jz.lastIndex = 0, jz.test(X);
  }
  var $E = -2147483648, YE = 2147483647;
  function WE(X) {
    return Number.isInteger(X) && X <= YE && X >= $E;
  }
  function JE(X) {
    return Number.isInteger(X);
  }
  function Rz() {
    return true;
  }
  var GE = /[^\\]\\Z/;
  function HE(X) {
    if (GE.test(X)) return false;
    try {
      return new RegExp(X), true;
    } catch (Q) {
      return false;
    }
  }
});
var vz = P((kz) => {
  Object.defineProperty(kz, "__esModule", { value: true });
  kz.formatLimitDefinition = void 0;
  var zE = cY(), Y1 = c(), i1 = Y1.operators, X8 = { formatMaximum: { okStr: "<=", ok: i1.LTE, fail: i1.GT }, formatMinimum: { okStr: ">=", ok: i1.GTE, fail: i1.LT }, formatExclusiveMaximum: { okStr: "<", ok: i1.LT, fail: i1.GTE }, formatExclusiveMinimum: { okStr: ">", ok: i1.GT, fail: i1.LTE } }, KE = { message: ({ keyword: X, schemaCode: Q }) => Y1.str`should be ${X8[X].okStr} ${Q}`, params: ({ keyword: X, schemaCode: Q }) => Y1._`{comparison: ${X8[X].okStr}, limit: ${Q}}` };
  kz.formatLimitDefinition = { keyword: Object.keys(X8), type: "string", schemaType: "string", $data: true, error: KE, code(X) {
    let { gen: Q, data: $, schemaCode: Y, keyword: W, it: J } = X, { opts: G, self: H } = J;
    if (!G.validateFormats) return;
    let B = new zE.KeywordCxt(J, H.RULES.all.format.definition, "format");
    if (B.$data) z();
    else K();
    function z() {
      let L = Q.scopeValue("formats", { ref: H.formats, code: G.code.formats }), U = Q.const("fmt", Y1._`${L}[${B.schemaCode}]`);
      X.fail$data((0, Y1.or)(Y1._`typeof ${U} != "object"`, Y1._`${U} instanceof RegExp`, Y1._`typeof ${U}.compare != "function"`, V(U)));
    }
    function K() {
      let L = B.schema, U = H.formats[L];
      if (!U || U === true) return;
      if (typeof U != "object" || U instanceof RegExp || typeof U.compare != "function") throw Error(`"${W}": format "${L}" does not define "compare" function`);
      let F = Q.scopeValue("formats", { key: L, ref: U, code: G.code.formats ? Y1._`${G.code.formats}${(0, Y1.getProperty)(L)}` : void 0 });
      X.fail$data(V(F));
    }
    function V(L) {
      return Y1._`${L}.compare(${$}, ${Y}) ${X8[W].fail} 0`;
    }
  }, dependencies: ["format"] };
  var UE = (X) => {
    return X.addKeyword(kz.formatLimitDefinition), X;
  };
  kz.default = UE;
});
var yz = P((G4, xz) => {
  Object.defineProperty(G4, "__esModule", { value: true });
  var r6 = Cz(), LE = vz(), aY = c(), Tz = new aY.Name("fullFormats"), qE = new aY.Name("fastFormats"), sY = (X, Q = { keywords: true }) => {
    if (Array.isArray(Q)) return _z(X, Q, r6.fullFormats, Tz), X;
    let [$, Y] = Q.mode === "fast" ? [r6.fastFormats, qE] : [r6.fullFormats, Tz], W = Q.formats || r6.formatNames;
    if (_z(X, W, $, Y), Q.keywords) (0, LE.default)(X);
    return X;
  };
  sY.get = (X, Q = "full") => {
    let Y = (Q === "fast" ? r6.fastFormats : r6.fullFormats)[X];
    if (!Y) throw Error(`Unknown format "${X}"`);
    return Y;
  };
  function _z(X, Q, $, Y) {
    var W, J;
    (W = (J = X.opts.code).formats) !== null && W !== void 0 || (J.formats = aY._`require("ajv-formats/dist/formats").${Y}`);
    for (let G of Q) X.addFormat(G, $[G]);
  }
  xz.exports = G4 = sY;
  Object.defineProperty(G4, "__esModule", { value: true });
  G4.default = sY;
});
var HK = 50;
function N6(X = HK) {
  let Q = new AbortController();
  return GK(X, Q.signal), Q;
}
var BK = typeof global == "object" && global && global.Object === Object && global;
var q7 = BK;
var zK = typeof self == "object" && self && self.Object === Object && self;
var KK = q7 || zK || Function("return this")();
var O6 = KK;
var UK = O6.Symbol;
var D6 = UK;
var F7 = Object.prototype;
var VK = F7.hasOwnProperty;
var LK = F7.toString;
var e6 = D6 ? D6.toStringTag : void 0;
function qK(X) {
  var Q = VK.call(X, e6), $ = X[e6];
  try {
    X[e6] = void 0;
    var Y = true;
  } catch (J) {
  }
  var W = LK.call(X);
  if (Y) if (Q) X[e6] = $;
  else delete X[e6];
  return W;
}
var N7 = qK;
var FK = Object.prototype;
var NK = FK.toString;
function OK(X) {
  return NK.call(X);
}
var O7 = OK;
var DK = "[object Null]";
var AK = "[object Undefined]";
var D7 = D6 ? D6.toStringTag : void 0;
function wK(X) {
  if (X == null) return X === void 0 ? AK : DK;
  return D7 && D7 in Object(X) ? N7(X) : O7(X);
}
var A7 = wK;
function MK(X) {
  var Q = typeof X;
  return X != null && (Q == "object" || Q == "function");
}
var z4 = MK;
var jK = "[object AsyncFunction]";
var RK = "[object Function]";
var EK = "[object GeneratorFunction]";
var IK = "[object Proxy]";
function bK(X) {
  if (!z4(X)) return false;
  var Q = A7(X);
  return Q == RK || Q == EK || Q == jK || Q == IK;
}
var w7 = bK;
var PK = O6["__core-js_shared__"];
var K4 = PK;
var M7 = function() {
  var X = /[^.]+$/.exec(K4 && K4.keys && K4.keys.IE_PROTO || "");
  return X ? "Symbol(src)_1." + X : "";
}();
function SK(X) {
  return !!M7 && M7 in X;
}
var j7 = SK;
var ZK = Function.prototype;
var CK = ZK.toString;
function kK(X) {
  if (X != null) {
    try {
      return CK.call(X);
    } catch (Q) {
    }
    try {
      return X + "";
    } catch (Q) {
    }
  }
  return "";
}
var R7 = kK;
var vK = /[\\^$.*+?()[\]{}|]/g;
var TK = /^\[object .+?Constructor\]$/;
var _K = Function.prototype;
var xK = Object.prototype;
var yK = _K.toString;
var gK = xK.hasOwnProperty;
var hK = RegExp("^" + yK.call(gK).replace(vK, "\\$&").replace(/hasOwnProperty|(function).*?(?=\\\()| for .+?(?=\\\])/g, "$1.*?") + "$");
function fK(X) {
  if (!z4(X) || j7(X)) return false;
  var Q = w7(X) ? hK : TK;
  return Q.test(R7(X));
}
var E7 = fK;
function uK(X, Q) {
  return X == null ? void 0 : X[Q];
}
var I7 = uK;
function lK(X, Q) {
  var $ = I7(X, Q);
  return E7($) ? $ : void 0;
}
var U4 = lK;
var mK = U4(Object, "create");
var q1 = mK;
function cK() {
  this.__data__ = q1 ? q1(null) : {}, this.size = 0;
}
var b7 = cK;
function pK(X) {
  var Q = this.has(X) && delete this.__data__[X];
  return this.size -= Q ? 1 : 0, Q;
}
var P7 = pK;
var dK = "__lodash_hash_undefined__";
var iK = Object.prototype;
var nK = iK.hasOwnProperty;
function rK(X) {
  var Q = this.__data__;
  if (q1) {
    var $ = Q[X];
    return $ === dK ? void 0 : $;
  }
  return nK.call(Q, X) ? Q[X] : void 0;
}
var S7 = rK;
var oK = Object.prototype;
var tK = oK.hasOwnProperty;
function aK(X) {
  var Q = this.__data__;
  return q1 ? Q[X] !== void 0 : tK.call(Q, X);
}
var Z7 = aK;
var sK = "__lodash_hash_undefined__";
function eK(X, Q) {
  var $ = this.__data__;
  return this.size += this.has(X) ? 0 : 1, $[X] = q1 && Q === void 0 ? sK : Q, this;
}
var C7 = eK;
function A6(X) {
  var Q = -1, $ = X == null ? 0 : X.length;
  this.clear();
  while (++Q < $) {
    var Y = X[Q];
    this.set(Y[0], Y[1]);
  }
}
A6.prototype.clear = b7;
A6.prototype.delete = P7;
A6.prototype.get = S7;
A6.prototype.has = Z7;
A6.prototype.set = C7;
var W8 = A6;
function XU() {
  this.__data__ = [], this.size = 0;
}
var k7 = XU;
function QU(X, Q) {
  return X === Q || X !== X && Q !== Q;
}
var v7 = QU;
function $U(X, Q) {
  var $ = X.length;
  while ($--) if (v7(X[$][0], Q)) return $;
  return -1;
}
var Z1 = $U;
var YU = Array.prototype;
var WU = YU.splice;
function JU(X) {
  var Q = this.__data__, $ = Z1(Q, X);
  if ($ < 0) return false;
  var Y = Q.length - 1;
  if ($ == Y) Q.pop();
  else WU.call(Q, $, 1);
  return --this.size, true;
}
var T7 = JU;
function GU(X) {
  var Q = this.__data__, $ = Z1(Q, X);
  return $ < 0 ? void 0 : Q[$][1];
}
var _7 = GU;
function HU(X) {
  return Z1(this.__data__, X) > -1;
}
var x7 = HU;
function BU(X, Q) {
  var $ = this.__data__, Y = Z1($, X);
  if (Y < 0) ++this.size, $.push([X, Q]);
  else $[Y][1] = Q;
  return this;
}
var y7 = BU;
function w6(X) {
  var Q = -1, $ = X == null ? 0 : X.length;
  this.clear();
  while (++Q < $) {
    var Y = X[Q];
    this.set(Y[0], Y[1]);
  }
}
w6.prototype.clear = k7;
w6.prototype.delete = T7;
w6.prototype.get = _7;
w6.prototype.has = x7;
w6.prototype.set = y7;
var g7 = w6;
var zU = U4(O6, "Map");
var h7 = zU;
function KU() {
  this.size = 0, this.__data__ = { hash: new W8(), map: new (h7 || g7)(), string: new W8() };
}
var f7 = KU;
function UU(X) {
  var Q = typeof X;
  return Q == "string" || Q == "number" || Q == "symbol" || Q == "boolean" ? X !== "__proto__" : X === null;
}
var u7 = UU;
function VU(X, Q) {
  var $ = X.__data__;
  return u7(Q) ? $[typeof Q == "string" ? "string" : "hash"] : $.map;
}
var C1 = VU;
function LU(X) {
  var Q = C1(this, X).delete(X);
  return this.size -= Q ? 1 : 0, Q;
}
var l7 = LU;
function qU(X) {
  return C1(this, X).get(X);
}
var m7 = qU;
function FU(X) {
  return C1(this, X).has(X);
}
var c7 = FU;
function NU(X, Q) {
  var $ = C1(this, X), Y = $.size;
  return $.set(X, Q), this.size += $.size == Y ? 0 : 1, this;
}
var p7 = NU;
function M6(X) {
  var Q = -1, $ = X == null ? 0 : X.length;
  this.clear();
  while (++Q < $) {
    var Y = X[Q];
    this.set(Y[0], Y[1]);
  }
}
M6.prototype.clear = f7;
M6.prototype.delete = l7;
M6.prototype.get = m7;
M6.prototype.has = c7;
M6.prototype.set = p7;
var J8 = M6;
var OU = "Expected a function";
function G8(X, Q) {
  if (typeof X != "function" || Q != null && typeof Q != "function") throw TypeError(OU);
  var $ = function() {
    var Y = arguments, W = Q ? Q.apply(this, Y) : Y[0], J = $.cache;
    if (J.has(W)) return J.get(W);
    var G = X.apply(this, Y);
    return $.cache = J.set(W, G) || J, G;
  };
  return $.cache = new (G8.Cache || J8)(), $;
}
G8.Cache = J8;
var r1 = G8;
function d7(X) {
  if (process.stderr.destroyed) return;
  for (let Q = 0; Q < X.length; Q += 2e3) process.stderr.write(X.substring(Q, Q + 2e3));
}
var i7 = r1((X) => {
  if (!X || X.trim() === "") return null;
  let Q = X.split(",").map((J) => J.trim()).filter(Boolean);
  if (Q.length === 0) return null;
  let $ = Q.some((J) => J.startsWith("!")), Y = Q.some((J) => !J.startsWith("!"));
  if ($ && Y) return null;
  let W = Q.map((J) => J.replace(/^!/, "").toLowerCase());
  return { include: $ ? [] : W, exclude: $ ? W : [], isExclusive: $ };
});
function DU(X) {
  let Q = [], $ = X.match(/^MCP server ["']([^"']+)["']/);
  if ($ && $[1]) Q.push("mcp"), Q.push($[1].toLowerCase());
  else {
    let J = X.match(/^([^:[]+):/);
    if (J && J[1]) Q.push(J[1].trim().toLowerCase());
  }
  let Y = X.match(/^\[([^\]]+)]/);
  if (Y && Y[1]) Q.push(Y[1].trim().toLowerCase());
  if (X.toLowerCase().includes("statsig event:")) Q.push("statsig");
  let W = X.match(/:\s*([^:]+?)(?:\s+(?:type|mode|status|event))?:/);
  if (W && W[1]) {
    let J = W[1].trim().toLowerCase();
    if (J.length < 30 && !J.includes(" ")) Q.push(J);
  }
  return Array.from(new Set(Q));
}
function AU(X, Q) {
  if (!Q) return true;
  if (X.length === 0) return false;
  if (Q.isExclusive) return !X.some(($) => Q.exclude.includes($));
  else return X.some(($) => Q.include.includes($));
}
function n7(X, Q) {
  if (!Q) return true;
  let $ = DU(X);
  return AU($, Q);
}
function V4() {
  return process.env.CLAUDE_CONFIG_DIR ?? wU(MU(), ".claude");
}
function H8(X) {
  if (!X) return false;
  if (typeof X === "boolean") return X;
  let Q = X.toLowerCase().trim();
  return ["1", "true", "yes", "on"].includes(Q);
}
function r7(X) {
  return { name: X, default: 3e4, validate: (Q) => {
    if (!Q) return { effective: 3e4, status: "valid" };
    let $ = parseInt(Q, 10);
    if (isNaN($) || $ <= 0) return { effective: 3e4, status: "invalid", message: `Invalid value "${Q}" (using default: 30000)` };
    if ($ > 15e4) return { effective: 15e4, status: "capped", message: `Capped from ${$} to 150000` };
    return { effective: $, status: "valid" };
  } };
}
var o7 = r7("BASH_MAX_OUTPUT_LENGTH");
var Db = r7("TASK_MAX_OUTPUT_LENGTH");
var t7 = { name: "CLAUDE_CODE_MAX_OUTPUT_TOKENS", default: 32e3, validate: (X) => {
  if (!X) return { effective: 32e3, status: "valid" };
  let Y = parseInt(X, 10);
  if (isNaN(Y) || Y <= 0) return { effective: 32e3, status: "invalid", message: `Invalid value "${X}" (using default: 32000)` };
  if (Y > 64e3) return { effective: 64e3, status: "capped", message: `Capped from ${Y} to 64000` };
  return { effective: Y, status: "valid" };
} };
function IU() {
  let X = "";
  if (typeof process < "u" && typeof process.cwd === "function") X = RU(jU());
  return { originalCwd: X, projectRoot: X, totalCostUSD: 0, totalAPIDuration: 0, totalAPIDurationWithoutRetries: 0, totalToolDuration: 0, startTime: Date.now(), lastInteractionTime: Date.now(), totalLinesAdded: 0, totalLinesRemoved: 0, hasUnknownModelCost: false, cwd: X, modelUsage: {}, mainLoopModelOverride: void 0, initialMainLoopModel: null, modelStrings: null, isInteractive: false, clientType: "cli", sessionIngressToken: void 0, oauthTokenFromFd: void 0, apiKeyFromFd: void 0, flagSettingsPath: void 0, allowedSettingSources: ["userSettings", "projectSettings", "localSettings", "flagSettings", "policySettings"], meter: null, sessionCounter: null, locCounter: null, prCounter: null, commitCounter: null, costCounter: null, tokenCounter: null, codeEditToolDecisionCounter: null, activeTimeCounter: null, sessionId: EU(), parentSessionId: void 0, loggerProvider: null, eventLogger: null, meterProvider: null, tracerProvider: null, agentColorMap: /* @__PURE__ */ new Map(), agentColorIndex: 0, envVarValidators: [o7, t7], lastAPIRequest: null, inMemoryErrorLog: [], inlinePlugins: [], useCoworkPlugins: false, sessionBypassPermissionsMode: false, sessionTrustAccepted: false, sessionPersistenceDisabled: false, hasExitedPlanMode: false, needsPlanModeExitAttachment: false, hasExitedDelegateMode: false, needsDelegateModeExitAttachment: false, lspRecommendationShownThisSession: false, initJsonSchema: null, registeredHooks: null, planSlugCache: /* @__PURE__ */ new Map(), teleportedSessionInfo: null, invokedSkills: /* @__PURE__ */ new Map(), slowOperations: [], sdkBetas: void 0, mainThreadAgentType: void 0, isRemoteMode: false };
}
var bU = IU();
function a7() {
  return bU.sessionId;
}
function s7({ writeFn: X, flushIntervalMs: Q = 1e3, maxBufferSize: $ = 100, immediateMode: Y = false }) {
  let W = [], J = null;
  function G() {
    if (J) clearTimeout(J), J = null;
  }
  function H() {
    if (W.length === 0) return;
    X(W.join("")), W = [], G();
  }
  function B() {
    if (!J) J = setTimeout(H, Q);
  }
  return { write(z) {
    if (Y) {
      X(z);
      return;
    }
    if (W.push(z), B(), W.length >= $) H();
  }, flush: H, dispose() {
    H();
  } };
}
var e7 = /* @__PURE__ */ new Set();
function XW(X) {
  return e7.add(X), () => e7.delete(X);
}
var B8 = 1 / 0;
function PU(X) {
  if (X === null) return "null";
  if (X === void 0) return "undefined";
  if (Array.isArray(X)) return `Array[${X.length}]`;
  if (typeof X === "object") return `Object{${Object.keys(X).length} keys}`;
  if (typeof X === "string") return `string(${X.length} chars)`;
  return typeof X;
}
function QW(X, Q) {
  let $ = performance.now();
  try {
    return Q();
  } finally {
    performance.now() - $ > B8;
  }
}
function Z0(X, Q, $) {
  let Y = PU(X);
  return QW(`JSON.stringify(${Y})`, () => JSON.stringify(X, Q, $));
}
var L4 = (X, Q) => {
  let $ = typeof X === "string" ? X.length : 0;
  return QW(`JSON.parse(${$} chars)`, () => JSON.parse(X, Q));
};
var SU = r1(() => {
  return H8(process.env.DEBUG) || H8(process.env.DEBUG_SDK) || process.argv.includes("--debug") || process.argv.includes("-d") || YW() || process.argv.some((X) => X.startsWith("--debug="));
});
var ZU = r1(() => {
  let X = process.argv.find(($) => $.startsWith("--debug="));
  if (!X) return null;
  let Q = X.substring(8);
  return i7(Q);
});
var YW = r1(() => {
  return process.argv.includes("--debug-to-stderr") || process.argv.includes("-d2e");
});
function CU(X) {
  if (typeof process > "u" || typeof process.versions > "u" || typeof process.versions.node > "u") return false;
  let Q = ZU();
  return n7(X, Q);
}
var kU = false;
var q4 = null;
function vU() {
  if (!q4) q4 = s7({ writeFn: (X) => {
    let Q = WW();
    if (!n0().existsSync(z8(Q))) n0().mkdirSync(z8(Q));
    n0().appendFileSync(Q, X), TU();
  }, flushIntervalMs: 1e3, maxBufferSize: 100, immediateMode: SU() }), XW(async () => q4?.dispose());
  return q4;
}
function k1(X, { level: Q } = { level: "debug" }) {
  if (!CU(X)) return;
  if (kU && X.includes(`
`)) X = Z0(X);
  let Y = `${(/* @__PURE__ */ new Date()).toISOString()} [${Q.toUpperCase()}] ${X.trim()}
`;
  if (YW()) {
    d7(Y);
    return;
  }
  vU().write(Y);
}
function WW() {
  return process.env.CLAUDE_CODE_DEBUG_LOGS_DIR ?? $W(V4(), "debug", `${a7()}.txt`);
}
var TU = r1(() => {
  if (process.argv[2] === "--ripgrep") return;
  try {
    let X = WW(), Q = z8(X), $ = $W(Q, "latest");
    if (!n0().existsSync(Q)) n0().mkdirSync(Q);
    if (n0().existsSync($)) try {
      n0().unlinkSync($);
    } catch {
    }
    n0().symlinkSync(X, $);
  } catch {
  }
});
function F0(X, Q) {
  let $ = performance.now();
  try {
    return Q();
  } finally {
    performance.now() - $ > B8;
  }
}
var yU = { cwd() {
  return process.cwd();
}, existsSync(X) {
  return F0(`existsSync(${X})`, () => f.existsSync(X));
}, async stat(X) {
  return _U(X);
}, statSync(X) {
  return F0(`statSync(${X})`, () => f.statSync(X));
}, lstatSync(X) {
  return F0(`lstatSync(${X})`, () => f.lstatSync(X));
}, readFileSync(X, Q) {
  return F0(`readFileSync(${X})`, () => f.readFileSync(X, { encoding: Q.encoding }));
}, readFileBytesSync(X) {
  return F0(`readFileBytesSync(${X})`, () => f.readFileSync(X));
}, readSync(X, Q) {
  return F0(`readSync(${X}, ${Q.length} bytes)`, () => {
    let $ = void 0;
    try {
      $ = f.openSync(X, "r");
      let Y = Buffer.alloc(Q.length), W = f.readSync($, Y, 0, Q.length, 0);
      return { buffer: Y, bytesRead: W };
    } finally {
      if ($) f.closeSync($);
    }
  });
}, appendFileSync(X, Q, $) {
  return F0(`appendFileSync(${X}, ${Q.length} chars)`, () => {
    if (!f.existsSync(X) && $?.mode !== void 0) {
      let Y = f.openSync(X, "a", $.mode);
      try {
        f.appendFileSync(Y, Q);
      } finally {
        f.closeSync(Y);
      }
    } else f.appendFileSync(X, Q);
  });
}, copyFileSync(X, Q) {
  return F0(`copyFileSync(${X} \u2192 ${Q})`, () => f.copyFileSync(X, Q));
}, unlinkSync(X) {
  return F0(`unlinkSync(${X})`, () => f.unlinkSync(X));
}, renameSync(X, Q) {
  return F0(`renameSync(${X} \u2192 ${Q})`, () => f.renameSync(X, Q));
}, linkSync(X, Q) {
  return F0(`linkSync(${X} \u2192 ${Q})`, () => f.linkSync(X, Q));
}, symlinkSync(X, Q) {
  return F0(`symlinkSync(${X} \u2192 ${Q})`, () => f.symlinkSync(X, Q));
}, readlinkSync(X) {
  return F0(`readlinkSync(${X})`, () => f.readlinkSync(X));
}, realpathSync(X) {
  return F0(`realpathSync(${X})`, () => f.realpathSync(X));
}, mkdirSync(X, Q) {
  return F0(`mkdirSync(${X})`, () => {
    if (!f.existsSync(X)) {
      let $ = { recursive: true };
      if (Q?.mode !== void 0) $.mode = Q.mode;
      f.mkdirSync(X, $);
    }
  });
}, readdirSync(X) {
  return F0(`readdirSync(${X})`, () => f.readdirSync(X, { withFileTypes: true }));
}, readdirStringSync(X) {
  return F0(`readdirStringSync(${X})`, () => f.readdirSync(X));
}, isDirEmptySync(X) {
  return F0(`isDirEmptySync(${X})`, () => {
    return this.readdirSync(X).length === 0;
  });
}, rmdirSync(X) {
  return F0(`rmdirSync(${X})`, () => f.rmdirSync(X));
}, rmSync(X, Q) {
  return F0(`rmSync(${X})`, () => f.rmSync(X, Q));
}, createWriteStream(X) {
  return f.createWriteStream(X);
} };
var gU = yU;
function n0() {
  return gU;
}
var F1 = class extends Error {
};
function j6() {
  return process.versions.bun !== void 0;
}
var F4 = null;
var GW = false;
function pU() {
  if (GW) return F4;
  if (GW = true, !process.env.DEBUG_CLAUDE_AGENT_SDK) return null;
  let X = JW(V4(), "debug");
  if (F4 = JW(X, `sdk-${uU()}.txt`), !mU(X)) cU(X, { recursive: true });
  return process.stderr.write(`SDK debug logs: ${F4}
`), F4;
}
function N1(X) {
  let Q = pU();
  if (!Q) return;
  let Y = `${(/* @__PURE__ */ new Date()).toISOString()} ${X}
`;
  lU(Q, Y);
}
function HW(X, Q) {
  let $ = { ...X };
  if (Q) {
    let Y = { sandbox: Q };
    if ($.settings) try {
      Y = { ...L4($.settings), sandbox: Q };
    } catch {
    }
    $.settings = Z0(Y);
  }
  return $;
}
var XX = class {
  options;
  process;
  processStdin;
  processStdout;
  ready = false;
  abortController;
  exitError;
  exitListeners = [];
  processExitHandler;
  abortHandler;
  constructor(X) {
    this.options = X;
    this.abortController = X.abortController || N6(), this.initialize();
  }
  getDefaultExecutable() {
    return j6() ? "bun" : "node";
  }
  spawnLocalProcess(X) {
    let { command: Q, args: $, cwd: Y, env: W, signal: J } = X, G = W.DEBUG_CLAUDE_AGENT_SDK || this.options.stderr ? "pipe" : "ignore", H = dU(Q, $, { cwd: Y, stdio: ["pipe", "pipe", G], signal: J, env: W, windowsHide: true });
    if (W.DEBUG_CLAUDE_AGENT_SDK || this.options.stderr) H.stderr.on("data", (z) => {
      let K = z.toString();
      if (N1(K), this.options.stderr) this.options.stderr(K);
    });
    return { stdin: H.stdin, stdout: H.stdout, get killed() {
      return H.killed;
    }, get exitCode() {
      return H.exitCode;
    }, kill: H.kill.bind(H), on: H.on.bind(H), once: H.once.bind(H), off: H.off.bind(H) };
  }
  initialize() {
    try {
      let { additionalDirectories: X = [], agent: Q, betas: $, cwd: Y, executable: W = this.getDefaultExecutable(), executableArgs: J = [], extraArgs: G = {}, pathToClaudeCodeExecutable: H, env: B = { ...process.env }, maxThinkingTokens: z, maxTurns: K, maxBudgetUsd: V, model: L, fallbackModel: U, jsonSchema: F, permissionMode: q, allowDangerouslySkipPermissions: N, permissionPromptToolName: A, continueConversation: M, resume: R, settingSources: S, allowedTools: C = [], disallowedTools: K0 = [], tools: U0, mcpServers: s, strictMcpConfig: D0, canUseTool: q0, includePartialMessages: W1, plugins: P1, sandbox: U6 } = this.options, d = ["--output-format", "stream-json", "--verbose", "--input-format", "stream-json"];
      if (z !== void 0) d.push("--max-thinking-tokens", z.toString());
      if (K) d.push("--max-turns", K.toString());
      if (V !== void 0) d.push("--max-budget-usd", V.toString());
      if (L) d.push("--model", L);
      if (Q) d.push("--agent", Q);
      if ($ && $.length > 0) d.push("--betas", $.join(","));
      if (F) d.push("--json-schema", Z0(F));
      if (B.DEBUG_CLAUDE_AGENT_SDK) d.push("--debug-to-stderr");
      if (q0) {
        if (A) throw Error("canUseTool callback cannot be used with permissionPromptToolName. Please use one or the other.");
        d.push("--permission-prompt-tool", "stdio");
      } else if (A) d.push("--permission-prompt-tool", A);
      if (M) d.push("--continue");
      if (R) d.push("--resume", R);
      if (C.length > 0) d.push("--allowedTools", C.join(","));
      if (K0.length > 0) d.push("--disallowedTools", K0.join(","));
      if (U0 !== void 0) if (Array.isArray(U0)) if (U0.length === 0) d.push("--tools", "");
      else d.push("--tools", U0.join(","));
      else d.push("--tools", "default");
      if (s && Object.keys(s).length > 0) d.push("--mcp-config", Z0({ mcpServers: s }));
      if (S) d.push("--setting-sources", S.join(","));
      if (D0) d.push("--strict-mcp-config");
      if (q) d.push("--permission-mode", q);
      if (N) d.push("--allow-dangerously-skip-permissions");
      if (U) {
        if (L && U === L) throw Error("Fallback model cannot be the same as the main model. Please specify a different model for fallbackModel option.");
        d.push("--fallback-model", U);
      }
      if (W1) d.push("--include-partial-messages");
      for (let S0 of X) d.push("--add-dir", S0);
      if (P1 && P1.length > 0) for (let S0 of P1) if (S0.type === "local") d.push("--plugin-dir", S0.path);
      else throw Error(`Unsupported plugin type: ${S0.type}`);
      if (this.options.forkSession) d.push("--fork-session");
      if (this.options.resumeSessionAt) d.push("--resume-session-at", this.options.resumeSessionAt);
      if (this.options.persistSession === false) d.push("--no-session-persistence");
      let Q8 = HW(G ?? {}, U6);
      for (let [S0, S1] of Object.entries(Q8)) if (S1 === null) d.push(`--${S0}`);
      else d.push(`--${S0}`, S1);
      if (!B.CLAUDE_CODE_ENTRYPOINT) B.CLAUDE_CODE_ENTRYPOINT = "sdk-ts";
      if (delete B.NODE_OPTIONS, B.DEBUG_CLAUDE_AGENT_SDK) B.DEBUG = "1";
      else delete B.DEBUG;
      let o6 = nU(H), V6 = o6 ? H : W, t6 = o6 ? [...J, ...d] : [...J, H, ...d], a6 = { command: V6, args: t6, cwd: Y, env: B, signal: this.abortController.signal };
      if (this.options.spawnClaudeCodeProcess) N1(`Spawning Claude Code (custom): ${V6} ${t6.join(" ")}`), this.process = this.options.spawnClaudeCodeProcess(a6);
      else {
        if (!n0().existsSync(H)) {
          let S1 = o6 ? `Claude Code native binary not found at ${H}. Please ensure Claude Code is installed via native installer or specify a valid path with options.pathToClaudeCodeExecutable.` : `Claude Code executable not found at ${H}. Is options.pathToClaudeCodeExecutable set?`;
          throw ReferenceError(S1);
        }
        N1(`Spawning Claude Code: ${V6} ${t6.join(" ")}`), this.process = this.spawnLocalProcess(a6);
      }
      this.processStdin = this.process.stdin, this.processStdout = this.process.stdout;
      let B4 = () => {
        if (this.process && !this.process.killed) this.process.kill("SIGTERM");
      };
      this.processExitHandler = B4, this.abortHandler = B4, process.on("exit", this.processExitHandler), this.abortController.signal.addEventListener("abort", this.abortHandler), this.process.on("error", (S0) => {
        if (this.ready = false, this.abortController.signal.aborted) this.exitError = new F1("Claude Code process aborted by user");
        else this.exitError = Error(`Failed to spawn Claude Code process: ${S0.message}`), N1(this.exitError.message);
      }), this.process.on("exit", (S0, S1) => {
        if (this.ready = false, this.abortController.signal.aborted) this.exitError = new F1("Claude Code process aborted by user");
        else {
          let s6 = this.getProcessExitError(S0, S1);
          if (s6) this.exitError = s6, N1(s6.message);
        }
      }), this.ready = true;
    } catch (X) {
      throw this.ready = false, X;
    }
  }
  getProcessExitError(X, Q) {
    if (X !== 0 && X !== null) return Error(`Claude Code process exited with code ${X}`);
    else if (Q) return Error(`Claude Code process terminated by signal ${Q}`);
    return;
  }
  write(X) {
    if (this.abortController.signal.aborted) throw new F1("Operation aborted");
    if (!this.ready || !this.processStdin) throw Error("ProcessTransport is not ready for writing");
    if (this.process?.killed || this.process?.exitCode !== null) throw Error("Cannot write to terminated process");
    if (this.exitError) throw Error(`Cannot write to process that exited with error: ${this.exitError.message}`);
    N1(`[ProcessTransport] Writing to stdin: ${X.substring(0, 100)}`);
    try {
      if (!this.processStdin.write(X)) N1("[ProcessTransport] Write buffer full, data queued");
    } catch (Q) {
      throw this.ready = false, Error(`Failed to write to process stdin: ${Q.message}`);
    }
  }
  close() {
    if (this.processStdin) this.processStdin.end(), this.processStdin = void 0;
    if (this.abortHandler) this.abortController.signal.removeEventListener("abort", this.abortHandler), this.abortHandler = void 0;
    for (let { handler: X } of this.exitListeners) this.process?.off("exit", X);
    if (this.exitListeners = [], this.process && !this.process.killed) this.process.kill("SIGTERM"), setTimeout(() => {
      if (this.process && !this.process.killed) this.process.kill("SIGKILL");
    }, 5e3);
    if (this.ready = false, this.processExitHandler) process.off("exit", this.processExitHandler), this.processExitHandler = void 0;
  }
  isReady() {
    return this.ready;
  }
  async *readMessages() {
    if (!this.processStdout) throw Error("ProcessTransport output stream not available");
    let X = iU({ input: this.processStdout });
    try {
      for await (let Q of X) if (Q.trim()) try {
        yield L4(Q);
      } catch ($) {
        throw N1(`Non-JSON stdout: ${Q}`), Error(`CLI output was not valid JSON. This may indicate an error during startup. Output: ${Q.slice(0, 200)}${Q.length > 200 ? "..." : ""}`);
      }
      await this.waitForExit();
    } catch (Q) {
      throw Q;
    } finally {
      X.close();
    }
  }
  endInput() {
    if (this.processStdin) this.processStdin.end();
  }
  getInputStream() {
    return this.processStdin;
  }
  onExit(X) {
    if (!this.process) return () => {
    };
    let Q = ($, Y) => {
      let W = this.getProcessExitError($, Y);
      X(W);
    };
    return this.process.on("exit", Q), this.exitListeners.push({ callback: X, handler: Q }), () => {
      if (this.process) this.process.off("exit", Q);
      let $ = this.exitListeners.findIndex((Y) => Y.handler === Q);
      if ($ !== -1) this.exitListeners.splice($, 1);
    };
  }
  async waitForExit() {
    if (!this.process) {
      if (this.exitError) throw this.exitError;
      return;
    }
    if (this.process.exitCode !== null || this.process.killed) {
      if (this.exitError) throw this.exitError;
      return;
    }
    return new Promise((X, Q) => {
      let $ = (W, J) => {
        if (this.abortController.signal.aborted) {
          Q(new F1("Operation aborted"));
          return;
        }
        let G = this.getProcessExitError(W, J);
        if (G) Q(G);
        else X();
      };
      this.process.once("exit", $);
      let Y = (W) => {
        this.process.off("exit", $), Q(W);
      };
      this.process.once("error", Y), this.process.once("exit", () => {
        this.process.off("error", Y);
      });
    });
  }
};
function nU(X) {
  return ![".js", ".mjs", ".tsx", ".ts", ".jsx"].some(($) => X.endsWith($));
}
var QX = class {
  returned;
  queue = [];
  readResolve;
  readReject;
  isDone = false;
  hasError;
  started = false;
  constructor(X) {
    this.returned = X;
  }
  [Symbol.asyncIterator]() {
    if (this.started) throw Error("Stream can only be iterated once");
    return this.started = true, this;
  }
  next() {
    if (this.queue.length > 0) return Promise.resolve({ done: false, value: this.queue.shift() });
    if (this.isDone) return Promise.resolve({ done: true, value: void 0 });
    if (this.hasError) return Promise.reject(this.hasError);
    return new Promise((X, Q) => {
      this.readResolve = X, this.readReject = Q;
    });
  }
  enqueue(X) {
    if (this.readResolve) {
      let Q = this.readResolve;
      this.readResolve = void 0, this.readReject = void 0, Q({ done: false, value: X });
    } else this.queue.push(X);
  }
  done() {
    if (this.isDone = true, this.readResolve) {
      let X = this.readResolve;
      this.readResolve = void 0, this.readReject = void 0, X({ done: true, value: void 0 });
    }
  }
  error(X) {
    if (this.hasError = X, this.readReject) {
      let Q = this.readReject;
      this.readResolve = void 0, this.readReject = void 0, Q(X);
    }
  }
  return() {
    if (this.isDone = true, this.returned) this.returned();
    return Promise.resolve({ done: true, value: void 0 });
  }
};
var K8 = class {
  sendMcpMessage;
  isClosed = false;
  constructor(X) {
    this.sendMcpMessage = X;
  }
  onclose;
  onerror;
  onmessage;
  async start() {
  }
  async send(X) {
    if (this.isClosed) throw Error("Transport is closed");
    this.sendMcpMessage(X);
  }
  async close() {
    if (this.isClosed) return;
    this.isClosed = true, this.onclose?.();
  }
};
var $X = class {
  transport;
  isSingleUserTurn;
  canUseTool;
  hooks;
  abortController;
  jsonSchema;
  initConfig;
  pendingControlResponses = /* @__PURE__ */ new Map();
  cleanupPerformed = false;
  sdkMessages;
  inputStream = new QX();
  initialization;
  cancelControllers = /* @__PURE__ */ new Map();
  hookCallbacks = /* @__PURE__ */ new Map();
  nextCallbackId = 0;
  sdkMcpTransports = /* @__PURE__ */ new Map();
  sdkMcpServerInstances = /* @__PURE__ */ new Map();
  pendingMcpResponses = /* @__PURE__ */ new Map();
  firstResultReceivedResolve;
  firstResultReceived = false;
  hasBidirectionalNeeds() {
    return this.sdkMcpTransports.size > 0 || this.hooks !== void 0 && Object.keys(this.hooks).length > 0 || this.canUseTool !== void 0;
  }
  constructor(X, Q, $, Y, W, J = /* @__PURE__ */ new Map(), G, H) {
    this.transport = X;
    this.isSingleUserTurn = Q;
    this.canUseTool = $;
    this.hooks = Y;
    this.abortController = W;
    this.jsonSchema = G;
    this.initConfig = H;
    for (let [B, z] of J) this.connectSdkMcpServer(B, z);
    this.sdkMessages = this.readSdkMessages(), this.readMessages(), this.initialization = this.initialize(), this.initialization.catch(() => {
    });
  }
  setError(X) {
    this.inputStream.error(X);
  }
  close() {
    this.cleanup();
  }
  cleanup(X) {
    if (this.cleanupPerformed) return;
    this.cleanupPerformed = true;
    try {
      this.transport.close(), this.pendingControlResponses.clear(), this.pendingMcpResponses.clear(), this.cancelControllers.clear(), this.hookCallbacks.clear();
      for (let Q of this.sdkMcpTransports.values()) try {
        Q.close();
      } catch {
      }
      if (this.sdkMcpTransports.clear(), X) this.inputStream.error(X);
      else this.inputStream.done();
    } catch (Q) {
    }
  }
  next(...[X]) {
    return this.sdkMessages.next(...[X]);
  }
  return(X) {
    return this.sdkMessages.return(X);
  }
  throw(X) {
    return this.sdkMessages.throw(X);
  }
  [Symbol.asyncIterator]() {
    return this.sdkMessages;
  }
  [Symbol.asyncDispose]() {
    return this.sdkMessages[Symbol.asyncDispose]();
  }
  async readMessages() {
    try {
      for await (let X of this.transport.readMessages()) {
        if (X.type === "control_response") {
          let Q = this.pendingControlResponses.get(X.response.request_id);
          if (Q) Q(X.response);
          continue;
        } else if (X.type === "control_request") {
          this.handleControlRequest(X);
          continue;
        } else if (X.type === "control_cancel_request") {
          this.handleControlCancelRequest(X);
          continue;
        } else if (X.type === "keep_alive") continue;
        if (X.type === "result") {
          if (this.firstResultReceived = true, this.firstResultReceivedResolve) this.firstResultReceivedResolve();
          if (this.isSingleUserTurn) k1("[Query.readMessages] First result received for single-turn query, closing stdin"), this.transport.endInput();
        }
        this.inputStream.enqueue(X);
      }
      if (this.firstResultReceivedResolve) this.firstResultReceivedResolve();
      this.inputStream.done(), this.cleanup();
    } catch (X) {
      if (this.firstResultReceivedResolve) this.firstResultReceivedResolve();
      this.inputStream.error(X), this.cleanup(X);
    }
  }
  async handleControlRequest(X) {
    let Q = new AbortController();
    this.cancelControllers.set(X.request_id, Q);
    try {
      let $ = await this.processControlRequest(X, Q.signal), Y = { type: "control_response", response: { subtype: "success", request_id: X.request_id, response: $ } };
      await Promise.resolve(this.transport.write(Z0(Y) + `
`));
    } catch ($) {
      let Y = { type: "control_response", response: { subtype: "error", request_id: X.request_id, error: $.message || String($) } };
      await Promise.resolve(this.transport.write(Z0(Y) + `
`));
    } finally {
      this.cancelControllers.delete(X.request_id);
    }
  }
  handleControlCancelRequest(X) {
    let Q = this.cancelControllers.get(X.request_id);
    if (Q) Q.abort(), this.cancelControllers.delete(X.request_id);
  }
  async processControlRequest(X, Q) {
    if (X.request.subtype === "can_use_tool") {
      if (!this.canUseTool) throw Error("canUseTool callback is not provided.");
      return { ...await this.canUseTool(X.request.tool_name, X.request.input, { signal: Q, suggestions: X.request.permission_suggestions, blockedPath: X.request.blocked_path, decisionReason: X.request.decision_reason, toolUseID: X.request.tool_use_id, agentID: X.request.agent_id }), toolUseID: X.request.tool_use_id };
    } else if (X.request.subtype === "hook_callback") return await this.handleHookCallbacks(X.request.callback_id, X.request.input, X.request.tool_use_id, Q);
    else if (X.request.subtype === "mcp_message") {
      let $ = X.request, Y = this.sdkMcpTransports.get($.server_name);
      if (!Y) throw Error(`SDK MCP server not found: ${$.server_name}`);
      if ("method" in $.message && "id" in $.message && $.message.id !== null) return { mcp_response: await this.handleMcpControlRequest($.server_name, $, Y) };
      else {
        if (Y.onmessage) Y.onmessage($.message);
        return { mcp_response: { jsonrpc: "2.0", result: {}, id: 0 } };
      }
    }
    throw Error("Unsupported control request subtype: " + X.request.subtype);
  }
  async *readSdkMessages() {
    for await (let X of this.inputStream) yield X;
  }
  async initialize() {
    let X;
    if (this.hooks) {
      X = {};
      for (let [W, J] of Object.entries(this.hooks)) if (J.length > 0) X[W] = J.map((G) => {
        let H = [];
        for (let B of G.hooks) {
          let z = `hook_${this.nextCallbackId++}`;
          this.hookCallbacks.set(z, B), H.push(z);
        }
        return { matcher: G.matcher, hookCallbackIds: H, timeout: G.timeout };
      });
    }
    let Q = this.sdkMcpTransports.size > 0 ? Array.from(this.sdkMcpTransports.keys()) : void 0, $ = { subtype: "initialize", hooks: X, sdkMcpServers: Q, jsonSchema: this.jsonSchema, systemPrompt: this.initConfig?.systemPrompt, appendSystemPrompt: this.initConfig?.appendSystemPrompt, agents: this.initConfig?.agents };
    return (await this.request($)).response;
  }
  async interrupt() {
    await this.request({ subtype: "interrupt" });
  }
  async setPermissionMode(X) {
    await this.request({ subtype: "set_permission_mode", mode: X });
  }
  async setModel(X) {
    await this.request({ subtype: "set_model", model: X });
  }
  async setMaxThinkingTokens(X) {
    await this.request({ subtype: "set_max_thinking_tokens", max_thinking_tokens: X });
  }
  async rewindFiles(X, Q) {
    return (await this.request({ subtype: "rewind_files", user_message_id: X, dry_run: Q?.dryRun })).response;
  }
  async processPendingPermissionRequests(X) {
    for (let Q of X) if (Q.request.subtype === "can_use_tool") this.handleControlRequest(Q).catch(() => {
    });
  }
  request(X) {
    let Q = Math.random().toString(36).substring(2, 15), $ = { request_id: Q, type: "control_request", request: X };
    return new Promise((Y, W) => {
      this.pendingControlResponses.set(Q, (J) => {
        if (J.subtype === "success") Y(J);
        else if (W(Error(J.error)), J.pending_permission_requests) this.processPendingPermissionRequests(J.pending_permission_requests);
      }), Promise.resolve(this.transport.write(Z0($) + `
`));
    });
  }
  async supportedCommands() {
    return (await this.initialization).commands;
  }
  async supportedModels() {
    return (await this.initialization).models;
  }
  async mcpServerStatus() {
    return (await this.request({ subtype: "mcp_status" })).response.mcpServers;
  }
  async setMcpServers(X) {
    let Q = {}, $ = {};
    for (let [H, B] of Object.entries(X)) if (B.type === "sdk" && "instance" in B) Q[H] = B.instance;
    else $[H] = B;
    let Y = new Set(this.sdkMcpServerInstances.keys()), W = new Set(Object.keys(Q));
    for (let H of Y) if (!W.has(H)) await this.disconnectSdkMcpServer(H);
    for (let [H, B] of Object.entries(Q)) if (!Y.has(H)) this.connectSdkMcpServer(H, B);
    let J = {};
    for (let H of Object.keys(Q)) J[H] = { type: "sdk", name: H };
    return (await this.request({ subtype: "mcp_set_servers", servers: { ...$, ...J } })).response;
  }
  async accountInfo() {
    return (await this.initialization).account;
  }
  async streamInput(X) {
    k1("[Query.streamInput] Starting to process input stream");
    try {
      let Q = 0;
      for await (let $ of X) {
        if (Q++, k1(`[Query.streamInput] Processing message ${Q}: ${$.type}`), this.abortController?.signal.aborted) break;
        await Promise.resolve(this.transport.write(Z0($) + `
`));
      }
      if (k1(`[Query.streamInput] Finished processing ${Q} messages from input stream`), Q > 0 && this.hasBidirectionalNeeds()) k1("[Query.streamInput] Has bidirectional needs, waiting for first result"), await this.waitForFirstResult();
      k1("[Query] Calling transport.endInput() to close stdin to CLI process"), this.transport.endInput();
    } catch (Q) {
      if (!(Q instanceof F1)) throw Q;
    }
  }
  waitForFirstResult() {
    if (this.firstResultReceived) return k1("[Query.waitForFirstResult] Result already received, returning immediately"), Promise.resolve();
    return new Promise((X) => {
      if (this.abortController?.signal.aborted) {
        X();
        return;
      }
      this.abortController?.signal.addEventListener("abort", () => X(), { once: true }), this.firstResultReceivedResolve = X;
    });
  }
  handleHookCallbacks(X, Q, $, Y) {
    let W = this.hookCallbacks.get(X);
    if (!W) throw Error(`No hook callback found for ID: ${X}`);
    return W(Q, $, { signal: Y });
  }
  connectSdkMcpServer(X, Q) {
    let $ = new K8((Y) => this.sendMcpServerMessageToCli(X, Y));
    this.sdkMcpTransports.set(X, $), this.sdkMcpServerInstances.set(X, Q), Q.connect($);
  }
  async disconnectSdkMcpServer(X) {
    let Q = this.sdkMcpTransports.get(X);
    if (Q) await Q.close(), this.sdkMcpTransports.delete(X);
    this.sdkMcpServerInstances.delete(X);
  }
  sendMcpServerMessageToCli(X, Q) {
    if ("id" in Q && Q.id !== null && Q.id !== void 0) {
      let Y = `${X}:${Q.id}`, W = this.pendingMcpResponses.get(Y);
      if (W) {
        W.resolve(Q), this.pendingMcpResponses.delete(Y);
        return;
      }
    }
    let $ = { type: "control_request", request_id: rU(), request: { subtype: "mcp_message", server_name: X, message: Q } };
    this.transport.write(Z0($) + `
`);
  }
  handleMcpControlRequest(X, Q, $) {
    let Y = "id" in Q.message ? Q.message.id : null, W = `${X}:${Y}`;
    return new Promise((J, G) => {
      let H = () => {
        this.pendingMcpResponses.delete(W);
      }, B = (K) => {
        H(), J(K);
      }, z = (K) => {
        H(), G(K);
      };
      if (this.pendingMcpResponses.set(W, { resolve: B, reject: z }), $.onmessage) $.onmessage(Q.message);
      else {
        H(), G(Error("No message handler registered"));
        return;
      }
    });
  }
};
var n;
(function(X) {
  X.assertEqual = (W) => {
  };
  function Q(W) {
  }
  X.assertIs = Q;
  function $(W) {
    throw Error();
  }
  X.assertNever = $, X.arrayToEnum = (W) => {
    let J = {};
    for (let G of W) J[G] = G;
    return J;
  }, X.getValidEnumValues = (W) => {
    let J = X.objectKeys(W).filter((H) => typeof W[W[H]] !== "number"), G = {};
    for (let H of J) G[H] = W[H];
    return X.objectValues(G);
  }, X.objectValues = (W) => {
    return X.objectKeys(W).map(function(J) {
      return W[J];
    });
  }, X.objectKeys = typeof Object.keys === "function" ? (W) => Object.keys(W) : (W) => {
    let J = [];
    for (let G in W) if (Object.prototype.hasOwnProperty.call(W, G)) J.push(G);
    return J;
  }, X.find = (W, J) => {
    for (let G of W) if (J(G)) return G;
    return;
  }, X.isInteger = typeof Number.isInteger === "function" ? (W) => Number.isInteger(W) : (W) => typeof W === "number" && Number.isFinite(W) && Math.floor(W) === W;
  function Y(W, J = " | ") {
    return W.map((G) => typeof G === "string" ? `'${G}'` : G).join(J);
  }
  X.joinValues = Y, X.jsonStringifyReplacer = (W, J) => {
    if (typeof J === "bigint") return J.toString();
    return J;
  };
})(n || (n = {}));
var KW;
(function(X) {
  X.mergeShapes = (Q, $) => {
    return { ...Q, ...$ };
  };
})(KW || (KW = {}));
var E = n.arrayToEnum(["string", "nan", "number", "integer", "float", "boolean", "date", "bigint", "symbol", "function", "undefined", "null", "array", "object", "unknown", "promise", "void", "never", "map", "set"]);
var O1 = (X) => {
  switch (typeof X) {
    case "undefined":
      return E.undefined;
    case "string":
      return E.string;
    case "number":
      return Number.isNaN(X) ? E.nan : E.number;
    case "boolean":
      return E.boolean;
    case "function":
      return E.function;
    case "bigint":
      return E.bigint;
    case "symbol":
      return E.symbol;
    case "object":
      if (Array.isArray(X)) return E.array;
      if (X === null) return E.null;
      if (X.then && typeof X.then === "function" && X.catch && typeof X.catch === "function") return E.promise;
      if (typeof Map < "u" && X instanceof Map) return E.map;
      if (typeof Set < "u" && X instanceof Set) return E.set;
      if (typeof Date < "u" && X instanceof Date) return E.date;
      return E.object;
    default:
      return E.unknown;
  }
};
var w = n.arrayToEnum(["invalid_type", "invalid_literal", "custom", "invalid_union", "invalid_union_discriminator", "invalid_enum_value", "unrecognized_keys", "invalid_arguments", "invalid_return_type", "invalid_date", "invalid_string", "too_small", "too_big", "invalid_intersection_types", "not_multiple_of", "not_finite"]);
var f0 = class _f0 extends Error {
  get errors() {
    return this.issues;
  }
  constructor(X) {
    super();
    this.issues = [], this.addIssue = ($) => {
      this.issues = [...this.issues, $];
    }, this.addIssues = ($ = []) => {
      this.issues = [...this.issues, ...$];
    };
    let Q = new.target.prototype;
    if (Object.setPrototypeOf) Object.setPrototypeOf(this, Q);
    else this.__proto__ = Q;
    this.name = "ZodError", this.issues = X;
  }
  format(X) {
    let Q = X || function(W) {
      return W.message;
    }, $ = { _errors: [] }, Y = (W) => {
      for (let J of W.issues) if (J.code === "invalid_union") J.unionErrors.map(Y);
      else if (J.code === "invalid_return_type") Y(J.returnTypeError);
      else if (J.code === "invalid_arguments") Y(J.argumentsError);
      else if (J.path.length === 0) $._errors.push(Q(J));
      else {
        let G = $, H = 0;
        while (H < J.path.length) {
          let B = J.path[H];
          if (H !== J.path.length - 1) G[B] = G[B] || { _errors: [] };
          else G[B] = G[B] || { _errors: [] }, G[B]._errors.push(Q(J));
          G = G[B], H++;
        }
      }
    };
    return Y(this), $;
  }
  static assert(X) {
    if (!(X instanceof _f0)) throw Error(`Not a ZodError: ${X}`);
  }
  toString() {
    return this.message;
  }
  get message() {
    return JSON.stringify(this.issues, n.jsonStringifyReplacer, 2);
  }
  get isEmpty() {
    return this.issues.length === 0;
  }
  flatten(X = (Q) => Q.message) {
    let Q = {}, $ = [];
    for (let Y of this.issues) if (Y.path.length > 0) {
      let W = Y.path[0];
      Q[W] = Q[W] || [], Q[W].push(X(Y));
    } else $.push(X(Y));
    return { formErrors: $, fieldErrors: Q };
  }
  get formErrors() {
    return this.flatten();
  }
};
f0.create = (X) => {
  return new f0(X);
};
var tU = (X, Q) => {
  let $;
  switch (X.code) {
    case w.invalid_type:
      if (X.received === E.undefined) $ = "Required";
      else $ = `Expected ${X.expected}, received ${X.received}`;
      break;
    case w.invalid_literal:
      $ = `Invalid literal value, expected ${JSON.stringify(X.expected, n.jsonStringifyReplacer)}`;
      break;
    case w.unrecognized_keys:
      $ = `Unrecognized key(s) in object: ${n.joinValues(X.keys, ", ")}`;
      break;
    case w.invalid_union:
      $ = "Invalid input";
      break;
    case w.invalid_union_discriminator:
      $ = `Invalid discriminator value. Expected ${n.joinValues(X.options)}`;
      break;
    case w.invalid_enum_value:
      $ = `Invalid enum value. Expected ${n.joinValues(X.options)}, received '${X.received}'`;
      break;
    case w.invalid_arguments:
      $ = "Invalid function arguments";
      break;
    case w.invalid_return_type:
      $ = "Invalid function return type";
      break;
    case w.invalid_date:
      $ = "Invalid date";
      break;
    case w.invalid_string:
      if (typeof X.validation === "object") if ("includes" in X.validation) {
        if ($ = `Invalid input: must include "${X.validation.includes}"`, typeof X.validation.position === "number") $ = `${$} at one or more positions greater than or equal to ${X.validation.position}`;
      } else if ("startsWith" in X.validation) $ = `Invalid input: must start with "${X.validation.startsWith}"`;
      else if ("endsWith" in X.validation) $ = `Invalid input: must end with "${X.validation.endsWith}"`;
      else n.assertNever(X.validation);
      else if (X.validation !== "regex") $ = `Invalid ${X.validation}`;
      else $ = "Invalid";
      break;
    case w.too_small:
      if (X.type === "array") $ = `Array must contain ${X.exact ? "exactly" : X.inclusive ? "at least" : "more than"} ${X.minimum} element(s)`;
      else if (X.type === "string") $ = `String must contain ${X.exact ? "exactly" : X.inclusive ? "at least" : "over"} ${X.minimum} character(s)`;
      else if (X.type === "number") $ = `Number must be ${X.exact ? "exactly equal to " : X.inclusive ? "greater than or equal to " : "greater than "}${X.minimum}`;
      else if (X.type === "bigint") $ = `Number must be ${X.exact ? "exactly equal to " : X.inclusive ? "greater than or equal to " : "greater than "}${X.minimum}`;
      else if (X.type === "date") $ = `Date must be ${X.exact ? "exactly equal to " : X.inclusive ? "greater than or equal to " : "greater than "}${new Date(Number(X.minimum))}`;
      else $ = "Invalid input";
      break;
    case w.too_big:
      if (X.type === "array") $ = `Array must contain ${X.exact ? "exactly" : X.inclusive ? "at most" : "less than"} ${X.maximum} element(s)`;
      else if (X.type === "string") $ = `String must contain ${X.exact ? "exactly" : X.inclusive ? "at most" : "under"} ${X.maximum} character(s)`;
      else if (X.type === "number") $ = `Number must be ${X.exact ? "exactly" : X.inclusive ? "less than or equal to" : "less than"} ${X.maximum}`;
      else if (X.type === "bigint") $ = `BigInt must be ${X.exact ? "exactly" : X.inclusive ? "less than or equal to" : "less than"} ${X.maximum}`;
      else if (X.type === "date") $ = `Date must be ${X.exact ? "exactly" : X.inclusive ? "smaller than or equal to" : "smaller than"} ${new Date(Number(X.maximum))}`;
      else $ = "Invalid input";
      break;
    case w.custom:
      $ = "Invalid input";
      break;
    case w.invalid_intersection_types:
      $ = "Intersection results could not be merged";
      break;
    case w.not_multiple_of:
      $ = `Number must be a multiple of ${X.multipleOf}`;
      break;
    case w.not_finite:
      $ = "Number must be finite";
      break;
    default:
      $ = Q.defaultError, n.assertNever(X);
  }
  return { message: $ };
};
var v1 = tU;
var aU = v1;
function YX() {
  return aU;
}
var N4 = (X) => {
  let { data: Q, path: $, errorMaps: Y, issueData: W } = X, J = [...$, ...W.path || []], G = { ...W, path: J };
  if (W.message !== void 0) return { ...W, path: J, message: W.message };
  let H = "", B = Y.filter((z) => !!z).slice().reverse();
  for (let z of B) H = z(G, { data: Q, defaultError: H }).message;
  return { ...W, path: J, message: H };
};
function b(X, Q) {
  let $ = YX(), Y = N4({ issueData: Q, data: X.data, path: X.path, errorMaps: [X.common.contextualErrorMap, X.schemaErrorMap, $, $ === v1 ? void 0 : v1].filter((W) => !!W) });
  X.common.issues.push(Y);
}
var I0 = class _I0 {
  constructor() {
    this.value = "valid";
  }
  dirty() {
    if (this.value === "valid") this.value = "dirty";
  }
  abort() {
    if (this.value !== "aborted") this.value = "aborted";
  }
  static mergeArray(X, Q) {
    let $ = [];
    for (let Y of Q) {
      if (Y.status === "aborted") return g;
      if (Y.status === "dirty") X.dirty();
      $.push(Y.value);
    }
    return { status: X.value, value: $ };
  }
  static async mergeObjectAsync(X, Q) {
    let $ = [];
    for (let Y of Q) {
      let W = await Y.key, J = await Y.value;
      $.push({ key: W, value: J });
    }
    return _I0.mergeObjectSync(X, $);
  }
  static mergeObjectSync(X, Q) {
    let $ = {};
    for (let Y of Q) {
      let { key: W, value: J } = Y;
      if (W.status === "aborted") return g;
      if (J.status === "aborted") return g;
      if (W.status === "dirty") X.dirty();
      if (J.status === "dirty") X.dirty();
      if (W.value !== "__proto__" && (typeof J.value < "u" || Y.alwaysSet)) $[W.value] = J.value;
    }
    return { status: X.value, value: $ };
  }
};
var g = Object.freeze({ status: "aborted" });
var R6 = (X) => ({ status: "dirty", value: X });
var C0 = (X) => ({ status: "valid", value: X });
var L8 = (X) => X.status === "aborted";
var q8 = (X) => X.status === "dirty";
var o1 = (X) => X.status === "valid";
var WX = (X) => typeof Promise < "u" && X instanceof Promise;
var Z;
(function(X) {
  X.errToObj = (Q) => typeof Q === "string" ? { message: Q } : Q || {}, X.toString = (Q) => typeof Q === "string" ? Q : Q?.message;
})(Z || (Z = {}));
var r0 = class {
  constructor(X, Q, $, Y) {
    this._cachedPath = [], this.parent = X, this.data = Q, this._path = $, this._key = Y;
  }
  get path() {
    if (!this._cachedPath.length) if (Array.isArray(this._key)) this._cachedPath.push(...this._path, ...this._key);
    else this._cachedPath.push(...this._path, this._key);
    return this._cachedPath;
  }
};
var UW = (X, Q) => {
  if (o1(Q)) return { success: true, data: Q.value };
  else {
    if (!X.common.issues.length) throw Error("Validation failed but no issues detected.");
    return { success: false, get error() {
      if (this._error) return this._error;
      let $ = new f0(X.common.issues);
      return this._error = $, this._error;
    } };
  }
};
function l(X) {
  if (!X) return {};
  let { errorMap: Q, invalid_type_error: $, required_error: Y, description: W } = X;
  if (Q && ($ || Y)) throw Error(`Can't use "invalid_type_error" or "required_error" in conjunction with custom error map.`);
  if (Q) return { errorMap: Q, description: W };
  return { errorMap: (G, H) => {
    let { message: B } = X;
    if (G.code === "invalid_enum_value") return { message: B ?? H.defaultError };
    if (typeof H.data > "u") return { message: B ?? Y ?? H.defaultError };
    if (G.code !== "invalid_type") return { message: H.defaultError };
    return { message: B ?? $ ?? H.defaultError };
  }, description: W };
}
var p = class {
  get description() {
    return this._def.description;
  }
  _getType(X) {
    return O1(X.data);
  }
  _getOrReturnCtx(X, Q) {
    return Q || { common: X.parent.common, data: X.data, parsedType: O1(X.data), schemaErrorMap: this._def.errorMap, path: X.path, parent: X.parent };
  }
  _processInputParams(X) {
    return { status: new I0(), ctx: { common: X.parent.common, data: X.data, parsedType: O1(X.data), schemaErrorMap: this._def.errorMap, path: X.path, parent: X.parent } };
  }
  _parseSync(X) {
    let Q = this._parse(X);
    if (WX(Q)) throw Error("Synchronous parse encountered promise.");
    return Q;
  }
  _parseAsync(X) {
    let Q = this._parse(X);
    return Promise.resolve(Q);
  }
  parse(X, Q) {
    let $ = this.safeParse(X, Q);
    if ($.success) return $.data;
    throw $.error;
  }
  safeParse(X, Q) {
    let $ = { common: { issues: [], async: Q?.async ?? false, contextualErrorMap: Q?.errorMap }, path: Q?.path || [], schemaErrorMap: this._def.errorMap, parent: null, data: X, parsedType: O1(X) }, Y = this._parseSync({ data: X, path: $.path, parent: $ });
    return UW($, Y);
  }
  "~validate"(X) {
    let Q = { common: { issues: [], async: !!this["~standard"].async }, path: [], schemaErrorMap: this._def.errorMap, parent: null, data: X, parsedType: O1(X) };
    if (!this["~standard"].async) try {
      let $ = this._parseSync({ data: X, path: [], parent: Q });
      return o1($) ? { value: $.value } : { issues: Q.common.issues };
    } catch ($) {
      if ($?.message?.toLowerCase()?.includes("encountered")) this["~standard"].async = true;
      Q.common = { issues: [], async: true };
    }
    return this._parseAsync({ data: X, path: [], parent: Q }).then(($) => o1($) ? { value: $.value } : { issues: Q.common.issues });
  }
  async parseAsync(X, Q) {
    let $ = await this.safeParseAsync(X, Q);
    if ($.success) return $.data;
    throw $.error;
  }
  async safeParseAsync(X, Q) {
    let $ = { common: { issues: [], contextualErrorMap: Q?.errorMap, async: true }, path: Q?.path || [], schemaErrorMap: this._def.errorMap, parent: null, data: X, parsedType: O1(X) }, Y = this._parse({ data: X, path: $.path, parent: $ }), W = await (WX(Y) ? Y : Promise.resolve(Y));
    return UW($, W);
  }
  refine(X, Q) {
    let $ = (Y) => {
      if (typeof Q === "string" || typeof Q > "u") return { message: Q };
      else if (typeof Q === "function") return Q(Y);
      else return Q;
    };
    return this._refinement((Y, W) => {
      let J = X(Y), G = () => W.addIssue({ code: w.custom, ...$(Y) });
      if (typeof Promise < "u" && J instanceof Promise) return J.then((H) => {
        if (!H) return G(), false;
        else return true;
      });
      if (!J) return G(), false;
      else return true;
    });
  }
  refinement(X, Q) {
    return this._refinement(($, Y) => {
      if (!X($)) return Y.addIssue(typeof Q === "function" ? Q($, Y) : Q), false;
      else return true;
    });
  }
  _refinement(X) {
    return new H1({ schema: this, typeName: j.ZodEffects, effect: { type: "refinement", refinement: X } });
  }
  superRefine(X) {
    return this._refinement(X);
  }
  constructor(X) {
    this.spa = this.safeParseAsync, this._def = X, this.parse = this.parse.bind(this), this.safeParse = this.safeParse.bind(this), this.parseAsync = this.parseAsync.bind(this), this.safeParseAsync = this.safeParseAsync.bind(this), this.spa = this.spa.bind(this), this.refine = this.refine.bind(this), this.refinement = this.refinement.bind(this), this.superRefine = this.superRefine.bind(this), this.optional = this.optional.bind(this), this.nullable = this.nullable.bind(this), this.nullish = this.nullish.bind(this), this.array = this.array.bind(this), this.promise = this.promise.bind(this), this.or = this.or.bind(this), this.and = this.and.bind(this), this.transform = this.transform.bind(this), this.brand = this.brand.bind(this), this.default = this.default.bind(this), this.catch = this.catch.bind(this), this.describe = this.describe.bind(this), this.pipe = this.pipe.bind(this), this.readonly = this.readonly.bind(this), this.isNullable = this.isNullable.bind(this), this.isOptional = this.isOptional.bind(this), this["~standard"] = { version: 1, vendor: "zod", validate: (Q) => this["~validate"](Q) };
  }
  optional() {
    return G1.create(this, this._def);
  }
  nullable() {
    return T1.create(this, this._def);
  }
  nullish() {
    return this.nullable().optional();
  }
  array() {
    return J1.create(this);
  }
  promise() {
    return S6.create(this, this._def);
  }
  or(X) {
    return zX.create([this, X], this._def);
  }
  and(X) {
    return KX.create(this, X, this._def);
  }
  transform(X) {
    return new H1({ ...l(this._def), schema: this, typeName: j.ZodEffects, effect: { type: "transform", transform: X } });
  }
  default(X) {
    let Q = typeof X === "function" ? X : () => X;
    return new qX({ ...l(this._def), innerType: this, defaultValue: Q, typeName: j.ZodDefault });
  }
  brand() {
    return new D8({ typeName: j.ZodBranded, type: this, ...l(this._def) });
  }
  catch(X) {
    let Q = typeof X === "function" ? X : () => X;
    return new FX({ ...l(this._def), innerType: this, catchValue: Q, typeName: j.ZodCatch });
  }
  describe(X) {
    return new this.constructor({ ...this._def, description: X });
  }
  pipe(X) {
    return E4.create(this, X);
  }
  readonly() {
    return NX.create(this);
  }
  isOptional() {
    return this.safeParse(void 0).success;
  }
  isNullable() {
    return this.safeParse(null).success;
  }
};
var sU = /^c[^\s-]{8,}$/i;
var eU = /^[0-9a-z]+$/;
var XV = /^[0-9A-HJKMNP-TV-Z]{26}$/i;
var QV = /^[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}$/i;
var $V = /^[a-z0-9_-]{21}$/i;
var YV = /^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*$/;
var WV = /^[-+]?P(?!$)(?:(?:[-+]?\d+Y)|(?:[-+]?\d+[.,]\d+Y$))?(?:(?:[-+]?\d+M)|(?:[-+]?\d+[.,]\d+M$))?(?:(?:[-+]?\d+W)|(?:[-+]?\d+[.,]\d+W$))?(?:(?:[-+]?\d+D)|(?:[-+]?\d+[.,]\d+D$))?(?:T(?=[\d+-])(?:(?:[-+]?\d+H)|(?:[-+]?\d+[.,]\d+H$))?(?:(?:[-+]?\d+M)|(?:[-+]?\d+[.,]\d+M$))?(?:[-+]?\d+(?:[.,]\d+)?S)?)??$/;
var JV = /^(?!\.)(?!.*\.\.)([A-Z0-9_'+\-\.]*)[A-Z0-9_+-]@([A-Z0-9][A-Z0-9\-]*\.)+[A-Z]{2,}$/i;
var GV = "^(\\p{Extended_Pictographic}|\\p{Emoji_Component})+$";
var F8;
var HV = /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$/;
var BV = /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\/(3[0-2]|[12]?[0-9])$/;
var zV = /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/;
var KV = /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\/(12[0-8]|1[01][0-9]|[1-9]?[0-9])$/;
var UV = /^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$/;
var VV = /^([0-9a-zA-Z-_]{4})*(([0-9a-zA-Z-_]{2}(==)?)|([0-9a-zA-Z-_]{3}(=)?))?$/;
var VW = "((\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-((0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])|(0[469]|11)-(0[1-9]|[12]\\d|30)|(02)-(0[1-9]|1\\d|2[0-8])))";
var LV = new RegExp(`^${VW}$`);
function LW(X) {
  let Q = "[0-5]\\d";
  if (X.precision) Q = `${Q}\\.\\d{${X.precision}}`;
  else if (X.precision == null) Q = `${Q}(\\.\\d+)?`;
  let $ = X.precision ? "+" : "?";
  return `([01]\\d|2[0-3]):[0-5]\\d(:${Q})${$}`;
}
function qV(X) {
  return new RegExp(`^${LW(X)}$`);
}
function FV(X) {
  let Q = `${VW}T${LW(X)}`, $ = [];
  if ($.push(X.local ? "Z?" : "Z"), X.offset) $.push("([+-]\\d{2}:?\\d{2})");
  return Q = `${Q}(${$.join("|")})`, new RegExp(`^${Q}$`);
}
function NV(X, Q) {
  if ((Q === "v4" || !Q) && HV.test(X)) return true;
  if ((Q === "v6" || !Q) && zV.test(X)) return true;
  return false;
}
function OV(X, Q) {
  if (!YV.test(X)) return false;
  try {
    let [$] = X.split(".");
    if (!$) return false;
    let Y = $.replace(/-/g, "+").replace(/_/g, "/").padEnd($.length + (4 - $.length % 4) % 4, "="), W = JSON.parse(atob(Y));
    if (typeof W !== "object" || W === null) return false;
    if ("typ" in W && W?.typ !== "JWT") return false;
    if (!W.alg) return false;
    if (Q && W.alg !== Q) return false;
    return true;
  } catch {
    return false;
  }
}
function DV(X, Q) {
  if ((Q === "v4" || !Q) && BV.test(X)) return true;
  if ((Q === "v6" || !Q) && KV.test(X)) return true;
  return false;
}
var A1 = class _A1 extends p {
  _parse(X) {
    if (this._def.coerce) X.data = String(X.data);
    if (this._getType(X) !== E.string) {
      let W = this._getOrReturnCtx(X);
      return b(W, { code: w.invalid_type, expected: E.string, received: W.parsedType }), g;
    }
    let $ = new I0(), Y = void 0;
    for (let W of this._def.checks) if (W.kind === "min") {
      if (X.data.length < W.value) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.too_small, minimum: W.value, type: "string", inclusive: true, exact: false, message: W.message }), $.dirty();
    } else if (W.kind === "max") {
      if (X.data.length > W.value) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.too_big, maximum: W.value, type: "string", inclusive: true, exact: false, message: W.message }), $.dirty();
    } else if (W.kind === "length") {
      let J = X.data.length > W.value, G = X.data.length < W.value;
      if (J || G) {
        if (Y = this._getOrReturnCtx(X, Y), J) b(Y, { code: w.too_big, maximum: W.value, type: "string", inclusive: true, exact: true, message: W.message });
        else if (G) b(Y, { code: w.too_small, minimum: W.value, type: "string", inclusive: true, exact: true, message: W.message });
        $.dirty();
      }
    } else if (W.kind === "email") {
      if (!JV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "email", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "emoji") {
      if (!F8) F8 = new RegExp(GV, "u");
      if (!F8.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "emoji", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "uuid") {
      if (!QV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "uuid", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "nanoid") {
      if (!$V.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "nanoid", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "cuid") {
      if (!sU.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "cuid", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "cuid2") {
      if (!eU.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "cuid2", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "ulid") {
      if (!XV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "ulid", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "url") try {
      new URL(X.data);
    } catch {
      Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "url", code: w.invalid_string, message: W.message }), $.dirty();
    }
    else if (W.kind === "regex") {
      if (W.regex.lastIndex = 0, !W.regex.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "regex", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "trim") X.data = X.data.trim();
    else if (W.kind === "includes") {
      if (!X.data.includes(W.value, W.position)) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.invalid_string, validation: { includes: W.value, position: W.position }, message: W.message }), $.dirty();
    } else if (W.kind === "toLowerCase") X.data = X.data.toLowerCase();
    else if (W.kind === "toUpperCase") X.data = X.data.toUpperCase();
    else if (W.kind === "startsWith") {
      if (!X.data.startsWith(W.value)) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.invalid_string, validation: { startsWith: W.value }, message: W.message }), $.dirty();
    } else if (W.kind === "endsWith") {
      if (!X.data.endsWith(W.value)) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.invalid_string, validation: { endsWith: W.value }, message: W.message }), $.dirty();
    } else if (W.kind === "datetime") {
      if (!FV(W).test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.invalid_string, validation: "datetime", message: W.message }), $.dirty();
    } else if (W.kind === "date") {
      if (!LV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.invalid_string, validation: "date", message: W.message }), $.dirty();
    } else if (W.kind === "time") {
      if (!qV(W).test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.invalid_string, validation: "time", message: W.message }), $.dirty();
    } else if (W.kind === "duration") {
      if (!WV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "duration", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "ip") {
      if (!NV(X.data, W.version)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "ip", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "jwt") {
      if (!OV(X.data, W.alg)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "jwt", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "cidr") {
      if (!DV(X.data, W.version)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "cidr", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "base64") {
      if (!UV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "base64", code: w.invalid_string, message: W.message }), $.dirty();
    } else if (W.kind === "base64url") {
      if (!VV.test(X.data)) Y = this._getOrReturnCtx(X, Y), b(Y, { validation: "base64url", code: w.invalid_string, message: W.message }), $.dirty();
    } else n.assertNever(W);
    return { status: $.value, value: X.data };
  }
  _regex(X, Q, $) {
    return this.refinement((Y) => X.test(Y), { validation: Q, code: w.invalid_string, ...Z.errToObj($) });
  }
  _addCheck(X) {
    return new _A1({ ...this._def, checks: [...this._def.checks, X] });
  }
  email(X) {
    return this._addCheck({ kind: "email", ...Z.errToObj(X) });
  }
  url(X) {
    return this._addCheck({ kind: "url", ...Z.errToObj(X) });
  }
  emoji(X) {
    return this._addCheck({ kind: "emoji", ...Z.errToObj(X) });
  }
  uuid(X) {
    return this._addCheck({ kind: "uuid", ...Z.errToObj(X) });
  }
  nanoid(X) {
    return this._addCheck({ kind: "nanoid", ...Z.errToObj(X) });
  }
  cuid(X) {
    return this._addCheck({ kind: "cuid", ...Z.errToObj(X) });
  }
  cuid2(X) {
    return this._addCheck({ kind: "cuid2", ...Z.errToObj(X) });
  }
  ulid(X) {
    return this._addCheck({ kind: "ulid", ...Z.errToObj(X) });
  }
  base64(X) {
    return this._addCheck({ kind: "base64", ...Z.errToObj(X) });
  }
  base64url(X) {
    return this._addCheck({ kind: "base64url", ...Z.errToObj(X) });
  }
  jwt(X) {
    return this._addCheck({ kind: "jwt", ...Z.errToObj(X) });
  }
  ip(X) {
    return this._addCheck({ kind: "ip", ...Z.errToObj(X) });
  }
  cidr(X) {
    return this._addCheck({ kind: "cidr", ...Z.errToObj(X) });
  }
  datetime(X) {
    if (typeof X === "string") return this._addCheck({ kind: "datetime", precision: null, offset: false, local: false, message: X });
    return this._addCheck({ kind: "datetime", precision: typeof X?.precision > "u" ? null : X?.precision, offset: X?.offset ?? false, local: X?.local ?? false, ...Z.errToObj(X?.message) });
  }
  date(X) {
    return this._addCheck({ kind: "date", message: X });
  }
  time(X) {
    if (typeof X === "string") return this._addCheck({ kind: "time", precision: null, message: X });
    return this._addCheck({ kind: "time", precision: typeof X?.precision > "u" ? null : X?.precision, ...Z.errToObj(X?.message) });
  }
  duration(X) {
    return this._addCheck({ kind: "duration", ...Z.errToObj(X) });
  }
  regex(X, Q) {
    return this._addCheck({ kind: "regex", regex: X, ...Z.errToObj(Q) });
  }
  includes(X, Q) {
    return this._addCheck({ kind: "includes", value: X, position: Q?.position, ...Z.errToObj(Q?.message) });
  }
  startsWith(X, Q) {
    return this._addCheck({ kind: "startsWith", value: X, ...Z.errToObj(Q) });
  }
  endsWith(X, Q) {
    return this._addCheck({ kind: "endsWith", value: X, ...Z.errToObj(Q) });
  }
  min(X, Q) {
    return this._addCheck({ kind: "min", value: X, ...Z.errToObj(Q) });
  }
  max(X, Q) {
    return this._addCheck({ kind: "max", value: X, ...Z.errToObj(Q) });
  }
  length(X, Q) {
    return this._addCheck({ kind: "length", value: X, ...Z.errToObj(Q) });
  }
  nonempty(X) {
    return this.min(1, Z.errToObj(X));
  }
  trim() {
    return new _A1({ ...this._def, checks: [...this._def.checks, { kind: "trim" }] });
  }
  toLowerCase() {
    return new _A1({ ...this._def, checks: [...this._def.checks, { kind: "toLowerCase" }] });
  }
  toUpperCase() {
    return new _A1({ ...this._def, checks: [...this._def.checks, { kind: "toUpperCase" }] });
  }
  get isDatetime() {
    return !!this._def.checks.find((X) => X.kind === "datetime");
  }
  get isDate() {
    return !!this._def.checks.find((X) => X.kind === "date");
  }
  get isTime() {
    return !!this._def.checks.find((X) => X.kind === "time");
  }
  get isDuration() {
    return !!this._def.checks.find((X) => X.kind === "duration");
  }
  get isEmail() {
    return !!this._def.checks.find((X) => X.kind === "email");
  }
  get isURL() {
    return !!this._def.checks.find((X) => X.kind === "url");
  }
  get isEmoji() {
    return !!this._def.checks.find((X) => X.kind === "emoji");
  }
  get isUUID() {
    return !!this._def.checks.find((X) => X.kind === "uuid");
  }
  get isNANOID() {
    return !!this._def.checks.find((X) => X.kind === "nanoid");
  }
  get isCUID() {
    return !!this._def.checks.find((X) => X.kind === "cuid");
  }
  get isCUID2() {
    return !!this._def.checks.find((X) => X.kind === "cuid2");
  }
  get isULID() {
    return !!this._def.checks.find((X) => X.kind === "ulid");
  }
  get isIP() {
    return !!this._def.checks.find((X) => X.kind === "ip");
  }
  get isCIDR() {
    return !!this._def.checks.find((X) => X.kind === "cidr");
  }
  get isBase64() {
    return !!this._def.checks.find((X) => X.kind === "base64");
  }
  get isBase64url() {
    return !!this._def.checks.find((X) => X.kind === "base64url");
  }
  get minLength() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "min") {
      if (X === null || Q.value > X) X = Q.value;
    }
    return X;
  }
  get maxLength() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "max") {
      if (X === null || Q.value < X) X = Q.value;
    }
    return X;
  }
};
A1.create = (X) => {
  return new A1({ checks: [], typeName: j.ZodString, coerce: X?.coerce ?? false, ...l(X) });
};
function AV(X, Q) {
  let $ = (X.toString().split(".")[1] || "").length, Y = (Q.toString().split(".")[1] || "").length, W = $ > Y ? $ : Y, J = Number.parseInt(X.toFixed(W).replace(".", "")), G = Number.parseInt(Q.toFixed(W).replace(".", ""));
  return J % G / 10 ** W;
}
var I6 = class _I6 extends p {
  constructor() {
    super(...arguments);
    this.min = this.gte, this.max = this.lte, this.step = this.multipleOf;
  }
  _parse(X) {
    if (this._def.coerce) X.data = Number(X.data);
    if (this._getType(X) !== E.number) {
      let W = this._getOrReturnCtx(X);
      return b(W, { code: w.invalid_type, expected: E.number, received: W.parsedType }), g;
    }
    let $ = void 0, Y = new I0();
    for (let W of this._def.checks) if (W.kind === "int") {
      if (!n.isInteger(X.data)) $ = this._getOrReturnCtx(X, $), b($, { code: w.invalid_type, expected: "integer", received: "float", message: W.message }), Y.dirty();
    } else if (W.kind === "min") {
      if (W.inclusive ? X.data < W.value : X.data <= W.value) $ = this._getOrReturnCtx(X, $), b($, { code: w.too_small, minimum: W.value, type: "number", inclusive: W.inclusive, exact: false, message: W.message }), Y.dirty();
    } else if (W.kind === "max") {
      if (W.inclusive ? X.data > W.value : X.data >= W.value) $ = this._getOrReturnCtx(X, $), b($, { code: w.too_big, maximum: W.value, type: "number", inclusive: W.inclusive, exact: false, message: W.message }), Y.dirty();
    } else if (W.kind === "multipleOf") {
      if (AV(X.data, W.value) !== 0) $ = this._getOrReturnCtx(X, $), b($, { code: w.not_multiple_of, multipleOf: W.value, message: W.message }), Y.dirty();
    } else if (W.kind === "finite") {
      if (!Number.isFinite(X.data)) $ = this._getOrReturnCtx(X, $), b($, { code: w.not_finite, message: W.message }), Y.dirty();
    } else n.assertNever(W);
    return { status: Y.value, value: X.data };
  }
  gte(X, Q) {
    return this.setLimit("min", X, true, Z.toString(Q));
  }
  gt(X, Q) {
    return this.setLimit("min", X, false, Z.toString(Q));
  }
  lte(X, Q) {
    return this.setLimit("max", X, true, Z.toString(Q));
  }
  lt(X, Q) {
    return this.setLimit("max", X, false, Z.toString(Q));
  }
  setLimit(X, Q, $, Y) {
    return new _I6({ ...this._def, checks: [...this._def.checks, { kind: X, value: Q, inclusive: $, message: Z.toString(Y) }] });
  }
  _addCheck(X) {
    return new _I6({ ...this._def, checks: [...this._def.checks, X] });
  }
  int(X) {
    return this._addCheck({ kind: "int", message: Z.toString(X) });
  }
  positive(X) {
    return this._addCheck({ kind: "min", value: 0, inclusive: false, message: Z.toString(X) });
  }
  negative(X) {
    return this._addCheck({ kind: "max", value: 0, inclusive: false, message: Z.toString(X) });
  }
  nonpositive(X) {
    return this._addCheck({ kind: "max", value: 0, inclusive: true, message: Z.toString(X) });
  }
  nonnegative(X) {
    return this._addCheck({ kind: "min", value: 0, inclusive: true, message: Z.toString(X) });
  }
  multipleOf(X, Q) {
    return this._addCheck({ kind: "multipleOf", value: X, message: Z.toString(Q) });
  }
  finite(X) {
    return this._addCheck({ kind: "finite", message: Z.toString(X) });
  }
  safe(X) {
    return this._addCheck({ kind: "min", inclusive: true, value: Number.MIN_SAFE_INTEGER, message: Z.toString(X) })._addCheck({ kind: "max", inclusive: true, value: Number.MAX_SAFE_INTEGER, message: Z.toString(X) });
  }
  get minValue() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "min") {
      if (X === null || Q.value > X) X = Q.value;
    }
    return X;
  }
  get maxValue() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "max") {
      if (X === null || Q.value < X) X = Q.value;
    }
    return X;
  }
  get isInt() {
    return !!this._def.checks.find((X) => X.kind === "int" || X.kind === "multipleOf" && n.isInteger(X.value));
  }
  get isFinite() {
    let X = null, Q = null;
    for (let $ of this._def.checks) if ($.kind === "finite" || $.kind === "int" || $.kind === "multipleOf") return true;
    else if ($.kind === "min") {
      if (Q === null || $.value > Q) Q = $.value;
    } else if ($.kind === "max") {
      if (X === null || $.value < X) X = $.value;
    }
    return Number.isFinite(Q) && Number.isFinite(X);
  }
};
I6.create = (X) => {
  return new I6({ checks: [], typeName: j.ZodNumber, coerce: X?.coerce || false, ...l(X) });
};
var b6 = class _b6 extends p {
  constructor() {
    super(...arguments);
    this.min = this.gte, this.max = this.lte;
  }
  _parse(X) {
    if (this._def.coerce) try {
      X.data = BigInt(X.data);
    } catch {
      return this._getInvalidInput(X);
    }
    if (this._getType(X) !== E.bigint) return this._getInvalidInput(X);
    let $ = void 0, Y = new I0();
    for (let W of this._def.checks) if (W.kind === "min") {
      if (W.inclusive ? X.data < W.value : X.data <= W.value) $ = this._getOrReturnCtx(X, $), b($, { code: w.too_small, type: "bigint", minimum: W.value, inclusive: W.inclusive, message: W.message }), Y.dirty();
    } else if (W.kind === "max") {
      if (W.inclusive ? X.data > W.value : X.data >= W.value) $ = this._getOrReturnCtx(X, $), b($, { code: w.too_big, type: "bigint", maximum: W.value, inclusive: W.inclusive, message: W.message }), Y.dirty();
    } else if (W.kind === "multipleOf") {
      if (X.data % W.value !== BigInt(0)) $ = this._getOrReturnCtx(X, $), b($, { code: w.not_multiple_of, multipleOf: W.value, message: W.message }), Y.dirty();
    } else n.assertNever(W);
    return { status: Y.value, value: X.data };
  }
  _getInvalidInput(X) {
    let Q = this._getOrReturnCtx(X);
    return b(Q, { code: w.invalid_type, expected: E.bigint, received: Q.parsedType }), g;
  }
  gte(X, Q) {
    return this.setLimit("min", X, true, Z.toString(Q));
  }
  gt(X, Q) {
    return this.setLimit("min", X, false, Z.toString(Q));
  }
  lte(X, Q) {
    return this.setLimit("max", X, true, Z.toString(Q));
  }
  lt(X, Q) {
    return this.setLimit("max", X, false, Z.toString(Q));
  }
  setLimit(X, Q, $, Y) {
    return new _b6({ ...this._def, checks: [...this._def.checks, { kind: X, value: Q, inclusive: $, message: Z.toString(Y) }] });
  }
  _addCheck(X) {
    return new _b6({ ...this._def, checks: [...this._def.checks, X] });
  }
  positive(X) {
    return this._addCheck({ kind: "min", value: BigInt(0), inclusive: false, message: Z.toString(X) });
  }
  negative(X) {
    return this._addCheck({ kind: "max", value: BigInt(0), inclusive: false, message: Z.toString(X) });
  }
  nonpositive(X) {
    return this._addCheck({ kind: "max", value: BigInt(0), inclusive: true, message: Z.toString(X) });
  }
  nonnegative(X) {
    return this._addCheck({ kind: "min", value: BigInt(0), inclusive: true, message: Z.toString(X) });
  }
  multipleOf(X, Q) {
    return this._addCheck({ kind: "multipleOf", value: X, message: Z.toString(Q) });
  }
  get minValue() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "min") {
      if (X === null || Q.value > X) X = Q.value;
    }
    return X;
  }
  get maxValue() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "max") {
      if (X === null || Q.value < X) X = Q.value;
    }
    return X;
  }
};
b6.create = (X) => {
  return new b6({ checks: [], typeName: j.ZodBigInt, coerce: X?.coerce ?? false, ...l(X) });
};
var O4 = class extends p {
  _parse(X) {
    if (this._def.coerce) X.data = Boolean(X.data);
    if (this._getType(X) !== E.boolean) {
      let $ = this._getOrReturnCtx(X);
      return b($, { code: w.invalid_type, expected: E.boolean, received: $.parsedType }), g;
    }
    return C0(X.data);
  }
};
O4.create = (X) => {
  return new O4({ typeName: j.ZodBoolean, coerce: X?.coerce || false, ...l(X) });
};
var GX = class _GX extends p {
  _parse(X) {
    if (this._def.coerce) X.data = new Date(X.data);
    if (this._getType(X) !== E.date) {
      let W = this._getOrReturnCtx(X);
      return b(W, { code: w.invalid_type, expected: E.date, received: W.parsedType }), g;
    }
    if (Number.isNaN(X.data.getTime())) {
      let W = this._getOrReturnCtx(X);
      return b(W, { code: w.invalid_date }), g;
    }
    let $ = new I0(), Y = void 0;
    for (let W of this._def.checks) if (W.kind === "min") {
      if (X.data.getTime() < W.value) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.too_small, message: W.message, inclusive: true, exact: false, minimum: W.value, type: "date" }), $.dirty();
    } else if (W.kind === "max") {
      if (X.data.getTime() > W.value) Y = this._getOrReturnCtx(X, Y), b(Y, { code: w.too_big, message: W.message, inclusive: true, exact: false, maximum: W.value, type: "date" }), $.dirty();
    } else n.assertNever(W);
    return { status: $.value, value: new Date(X.data.getTime()) };
  }
  _addCheck(X) {
    return new _GX({ ...this._def, checks: [...this._def.checks, X] });
  }
  min(X, Q) {
    return this._addCheck({ kind: "min", value: X.getTime(), message: Z.toString(Q) });
  }
  max(X, Q) {
    return this._addCheck({ kind: "max", value: X.getTime(), message: Z.toString(Q) });
  }
  get minDate() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "min") {
      if (X === null || Q.value > X) X = Q.value;
    }
    return X != null ? new Date(X) : null;
  }
  get maxDate() {
    let X = null;
    for (let Q of this._def.checks) if (Q.kind === "max") {
      if (X === null || Q.value < X) X = Q.value;
    }
    return X != null ? new Date(X) : null;
  }
};
GX.create = (X) => {
  return new GX({ checks: [], coerce: X?.coerce || false, typeName: j.ZodDate, ...l(X) });
};
var D4 = class extends p {
  _parse(X) {
    if (this._getType(X) !== E.symbol) {
      let $ = this._getOrReturnCtx(X);
      return b($, { code: w.invalid_type, expected: E.symbol, received: $.parsedType }), g;
    }
    return C0(X.data);
  }
};
D4.create = (X) => {
  return new D4({ typeName: j.ZodSymbol, ...l(X) });
};
var HX = class extends p {
  _parse(X) {
    if (this._getType(X) !== E.undefined) {
      let $ = this._getOrReturnCtx(X);
      return b($, { code: w.invalid_type, expected: E.undefined, received: $.parsedType }), g;
    }
    return C0(X.data);
  }
};
HX.create = (X) => {
  return new HX({ typeName: j.ZodUndefined, ...l(X) });
};
var BX = class extends p {
  _parse(X) {
    if (this._getType(X) !== E.null) {
      let $ = this._getOrReturnCtx(X);
      return b($, { code: w.invalid_type, expected: E.null, received: $.parsedType }), g;
    }
    return C0(X.data);
  }
};
BX.create = (X) => {
  return new BX({ typeName: j.ZodNull, ...l(X) });
};
var A4 = class extends p {
  constructor() {
    super(...arguments);
    this._any = true;
  }
  _parse(X) {
    return C0(X.data);
  }
};
A4.create = (X) => {
  return new A4({ typeName: j.ZodAny, ...l(X) });
};
var t1 = class extends p {
  constructor() {
    super(...arguments);
    this._unknown = true;
  }
  _parse(X) {
    return C0(X.data);
  }
};
t1.create = (X) => {
  return new t1({ typeName: j.ZodUnknown, ...l(X) });
};
var w1 = class extends p {
  _parse(X) {
    let Q = this._getOrReturnCtx(X);
    return b(Q, { code: w.invalid_type, expected: E.never, received: Q.parsedType }), g;
  }
};
w1.create = (X) => {
  return new w1({ typeName: j.ZodNever, ...l(X) });
};
var w4 = class extends p {
  _parse(X) {
    if (this._getType(X) !== E.undefined) {
      let $ = this._getOrReturnCtx(X);
      return b($, { code: w.invalid_type, expected: E.void, received: $.parsedType }), g;
    }
    return C0(X.data);
  }
};
w4.create = (X) => {
  return new w4({ typeName: j.ZodVoid, ...l(X) });
};
var J1 = class _J1 extends p {
  _parse(X) {
    let { ctx: Q, status: $ } = this._processInputParams(X), Y = this._def;
    if (Q.parsedType !== E.array) return b(Q, { code: w.invalid_type, expected: E.array, received: Q.parsedType }), g;
    if (Y.exactLength !== null) {
      let J = Q.data.length > Y.exactLength.value, G = Q.data.length < Y.exactLength.value;
      if (J || G) b(Q, { code: J ? w.too_big : w.too_small, minimum: G ? Y.exactLength.value : void 0, maximum: J ? Y.exactLength.value : void 0, type: "array", inclusive: true, exact: true, message: Y.exactLength.message }), $.dirty();
    }
    if (Y.minLength !== null) {
      if (Q.data.length < Y.minLength.value) b(Q, { code: w.too_small, minimum: Y.minLength.value, type: "array", inclusive: true, exact: false, message: Y.minLength.message }), $.dirty();
    }
    if (Y.maxLength !== null) {
      if (Q.data.length > Y.maxLength.value) b(Q, { code: w.too_big, maximum: Y.maxLength.value, type: "array", inclusive: true, exact: false, message: Y.maxLength.message }), $.dirty();
    }
    if (Q.common.async) return Promise.all([...Q.data].map((J, G) => {
      return Y.type._parseAsync(new r0(Q, J, Q.path, G));
    })).then((J) => {
      return I0.mergeArray($, J);
    });
    let W = [...Q.data].map((J, G) => {
      return Y.type._parseSync(new r0(Q, J, Q.path, G));
    });
    return I0.mergeArray($, W);
  }
  get element() {
    return this._def.type;
  }
  min(X, Q) {
    return new _J1({ ...this._def, minLength: { value: X, message: Z.toString(Q) } });
  }
  max(X, Q) {
    return new _J1({ ...this._def, maxLength: { value: X, message: Z.toString(Q) } });
  }
  length(X, Q) {
    return new _J1({ ...this._def, exactLength: { value: X, message: Z.toString(Q) } });
  }
  nonempty(X) {
    return this.min(1, X);
  }
};
J1.create = (X, Q) => {
  return new J1({ type: X, minLength: null, maxLength: null, exactLength: null, typeName: j.ZodArray, ...l(Q) });
};
function E6(X) {
  if (X instanceof V0) {
    let Q = {};
    for (let $ in X.shape) {
      let Y = X.shape[$];
      Q[$] = G1.create(E6(Y));
    }
    return new V0({ ...X._def, shape: () => Q });
  } else if (X instanceof J1) return new J1({ ...X._def, type: E6(X.element) });
  else if (X instanceof G1) return G1.create(E6(X.unwrap()));
  else if (X instanceof T1) return T1.create(E6(X.unwrap()));
  else if (X instanceof M1) return M1.create(X.items.map((Q) => E6(Q)));
  else return X;
}
var V0 = class _V0 extends p {
  constructor() {
    super(...arguments);
    this._cached = null, this.nonstrict = this.passthrough, this.augment = this.extend;
  }
  _getCached() {
    if (this._cached !== null) return this._cached;
    let X = this._def.shape(), Q = n.objectKeys(X);
    return this._cached = { shape: X, keys: Q }, this._cached;
  }
  _parse(X) {
    if (this._getType(X) !== E.object) {
      let B = this._getOrReturnCtx(X);
      return b(B, { code: w.invalid_type, expected: E.object, received: B.parsedType }), g;
    }
    let { status: $, ctx: Y } = this._processInputParams(X), { shape: W, keys: J } = this._getCached(), G = [];
    if (!(this._def.catchall instanceof w1 && this._def.unknownKeys === "strip")) {
      for (let B in Y.data) if (!J.includes(B)) G.push(B);
    }
    let H = [];
    for (let B of J) {
      let z = W[B], K = Y.data[B];
      H.push({ key: { status: "valid", value: B }, value: z._parse(new r0(Y, K, Y.path, B)), alwaysSet: B in Y.data });
    }
    if (this._def.catchall instanceof w1) {
      let B = this._def.unknownKeys;
      if (B === "passthrough") for (let z of G) H.push({ key: { status: "valid", value: z }, value: { status: "valid", value: Y.data[z] } });
      else if (B === "strict") {
        if (G.length > 0) b(Y, { code: w.unrecognized_keys, keys: G }), $.dirty();
      } else if (B === "strip") ;
      else throw Error("Internal ZodObject error: invalid unknownKeys value.");
    } else {
      let B = this._def.catchall;
      for (let z of G) {
        let K = Y.data[z];
        H.push({ key: { status: "valid", value: z }, value: B._parse(new r0(Y, K, Y.path, z)), alwaysSet: z in Y.data });
      }
    }
    if (Y.common.async) return Promise.resolve().then(async () => {
      let B = [];
      for (let z of H) {
        let K = await z.key, V = await z.value;
        B.push({ key: K, value: V, alwaysSet: z.alwaysSet });
      }
      return B;
    }).then((B) => {
      return I0.mergeObjectSync($, B);
    });
    else return I0.mergeObjectSync($, H);
  }
  get shape() {
    return this._def.shape();
  }
  strict(X) {
    return Z.errToObj, new _V0({ ...this._def, unknownKeys: "strict", ...X !== void 0 ? { errorMap: (Q, $) => {
      let Y = this._def.errorMap?.(Q, $).message ?? $.defaultError;
      if (Q.code === "unrecognized_keys") return { message: Z.errToObj(X).message ?? Y };
      return { message: Y };
    } } : {} });
  }
  strip() {
    return new _V0({ ...this._def, unknownKeys: "strip" });
  }
  passthrough() {
    return new _V0({ ...this._def, unknownKeys: "passthrough" });
  }
  extend(X) {
    return new _V0({ ...this._def, shape: () => ({ ...this._def.shape(), ...X }) });
  }
  merge(X) {
    return new _V0({ unknownKeys: X._def.unknownKeys, catchall: X._def.catchall, shape: () => ({ ...this._def.shape(), ...X._def.shape() }), typeName: j.ZodObject });
  }
  setKey(X, Q) {
    return this.augment({ [X]: Q });
  }
  catchall(X) {
    return new _V0({ ...this._def, catchall: X });
  }
  pick(X) {
    let Q = {};
    for (let $ of n.objectKeys(X)) if (X[$] && this.shape[$]) Q[$] = this.shape[$];
    return new _V0({ ...this._def, shape: () => Q });
  }
  omit(X) {
    let Q = {};
    for (let $ of n.objectKeys(this.shape)) if (!X[$]) Q[$] = this.shape[$];
    return new _V0({ ...this._def, shape: () => Q });
  }
  deepPartial() {
    return E6(this);
  }
  partial(X) {
    let Q = {};
    for (let $ of n.objectKeys(this.shape)) {
      let Y = this.shape[$];
      if (X && !X[$]) Q[$] = Y;
      else Q[$] = Y.optional();
    }
    return new _V0({ ...this._def, shape: () => Q });
  }
  required(X) {
    let Q = {};
    for (let $ of n.objectKeys(this.shape)) if (X && !X[$]) Q[$] = this.shape[$];
    else {
      let W = this.shape[$];
      while (W instanceof G1) W = W._def.innerType;
      Q[$] = W;
    }
    return new _V0({ ...this._def, shape: () => Q });
  }
  keyof() {
    return qW(n.objectKeys(this.shape));
  }
};
V0.create = (X, Q) => {
  return new V0({ shape: () => X, unknownKeys: "strip", catchall: w1.create(), typeName: j.ZodObject, ...l(Q) });
};
V0.strictCreate = (X, Q) => {
  return new V0({ shape: () => X, unknownKeys: "strict", catchall: w1.create(), typeName: j.ZodObject, ...l(Q) });
};
V0.lazycreate = (X, Q) => {
  return new V0({ shape: X, unknownKeys: "strip", catchall: w1.create(), typeName: j.ZodObject, ...l(Q) });
};
var zX = class extends p {
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X), $ = this._def.options;
    function Y(W) {
      for (let G of W) if (G.result.status === "valid") return G.result;
      for (let G of W) if (G.result.status === "dirty") return Q.common.issues.push(...G.ctx.common.issues), G.result;
      let J = W.map((G) => new f0(G.ctx.common.issues));
      return b(Q, { code: w.invalid_union, unionErrors: J }), g;
    }
    if (Q.common.async) return Promise.all($.map(async (W) => {
      let J = { ...Q, common: { ...Q.common, issues: [] }, parent: null };
      return { result: await W._parseAsync({ data: Q.data, path: Q.path, parent: J }), ctx: J };
    })).then(Y);
    else {
      let W = void 0, J = [];
      for (let H of $) {
        let B = { ...Q, common: { ...Q.common, issues: [] }, parent: null }, z = H._parseSync({ data: Q.data, path: Q.path, parent: B });
        if (z.status === "valid") return z;
        else if (z.status === "dirty" && !W) W = { result: z, ctx: B };
        if (B.common.issues.length) J.push(B.common.issues);
      }
      if (W) return Q.common.issues.push(...W.ctx.common.issues), W.result;
      let G = J.map((H) => new f0(H));
      return b(Q, { code: w.invalid_union, unionErrors: G }), g;
    }
  }
  get options() {
    return this._def.options;
  }
};
zX.create = (X, Q) => {
  return new zX({ options: X, typeName: j.ZodUnion, ...l(Q) });
};
var D1 = (X) => {
  if (X instanceof UX) return D1(X.schema);
  else if (X instanceof H1) return D1(X.innerType());
  else if (X instanceof VX) return [X.value];
  else if (X instanceof a1) return X.options;
  else if (X instanceof LX) return n.objectValues(X.enum);
  else if (X instanceof qX) return D1(X._def.innerType);
  else if (X instanceof HX) return [void 0];
  else if (X instanceof BX) return [null];
  else if (X instanceof G1) return [void 0, ...D1(X.unwrap())];
  else if (X instanceof T1) return [null, ...D1(X.unwrap())];
  else if (X instanceof D8) return D1(X.unwrap());
  else if (X instanceof NX) return D1(X.unwrap());
  else if (X instanceof FX) return D1(X._def.innerType);
  else return [];
};
var O8 = class _O8 extends p {
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X);
    if (Q.parsedType !== E.object) return b(Q, { code: w.invalid_type, expected: E.object, received: Q.parsedType }), g;
    let $ = this.discriminator, Y = Q.data[$], W = this.optionsMap.get(Y);
    if (!W) return b(Q, { code: w.invalid_union_discriminator, options: Array.from(this.optionsMap.keys()), path: [$] }), g;
    if (Q.common.async) return W._parseAsync({ data: Q.data, path: Q.path, parent: Q });
    else return W._parseSync({ data: Q.data, path: Q.path, parent: Q });
  }
  get discriminator() {
    return this._def.discriminator;
  }
  get options() {
    return this._def.options;
  }
  get optionsMap() {
    return this._def.optionsMap;
  }
  static create(X, Q, $) {
    let Y = /* @__PURE__ */ new Map();
    for (let W of Q) {
      let J = D1(W.shape[X]);
      if (!J.length) throw Error(`A discriminator value for key \`${X}\` could not be extracted from all schema options`);
      for (let G of J) {
        if (Y.has(G)) throw Error(`Discriminator property ${String(X)} has duplicate value ${String(G)}`);
        Y.set(G, W);
      }
    }
    return new _O8({ typeName: j.ZodDiscriminatedUnion, discriminator: X, options: Q, optionsMap: Y, ...l($) });
  }
};
function N8(X, Q) {
  let $ = O1(X), Y = O1(Q);
  if (X === Q) return { valid: true, data: X };
  else if ($ === E.object && Y === E.object) {
    let W = n.objectKeys(Q), J = n.objectKeys(X).filter((H) => W.indexOf(H) !== -1), G = { ...X, ...Q };
    for (let H of J) {
      let B = N8(X[H], Q[H]);
      if (!B.valid) return { valid: false };
      G[H] = B.data;
    }
    return { valid: true, data: G };
  } else if ($ === E.array && Y === E.array) {
    if (X.length !== Q.length) return { valid: false };
    let W = [];
    for (let J = 0; J < X.length; J++) {
      let G = X[J], H = Q[J], B = N8(G, H);
      if (!B.valid) return { valid: false };
      W.push(B.data);
    }
    return { valid: true, data: W };
  } else if ($ === E.date && Y === E.date && +X === +Q) return { valid: true, data: X };
  else return { valid: false };
}
var KX = class extends p {
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X), Y = (W, J) => {
      if (L8(W) || L8(J)) return g;
      let G = N8(W.value, J.value);
      if (!G.valid) return b($, { code: w.invalid_intersection_types }), g;
      if (q8(W) || q8(J)) Q.dirty();
      return { status: Q.value, value: G.data };
    };
    if ($.common.async) return Promise.all([this._def.left._parseAsync({ data: $.data, path: $.path, parent: $ }), this._def.right._parseAsync({ data: $.data, path: $.path, parent: $ })]).then(([W, J]) => Y(W, J));
    else return Y(this._def.left._parseSync({ data: $.data, path: $.path, parent: $ }), this._def.right._parseSync({ data: $.data, path: $.path, parent: $ }));
  }
};
KX.create = (X, Q, $) => {
  return new KX({ left: X, right: Q, typeName: j.ZodIntersection, ...l($) });
};
var M1 = class _M1 extends p {
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X);
    if ($.parsedType !== E.array) return b($, { code: w.invalid_type, expected: E.array, received: $.parsedType }), g;
    if ($.data.length < this._def.items.length) return b($, { code: w.too_small, minimum: this._def.items.length, inclusive: true, exact: false, type: "array" }), g;
    if (!this._def.rest && $.data.length > this._def.items.length) b($, { code: w.too_big, maximum: this._def.items.length, inclusive: true, exact: false, type: "array" }), Q.dirty();
    let W = [...$.data].map((J, G) => {
      let H = this._def.items[G] || this._def.rest;
      if (!H) return null;
      return H._parse(new r0($, J, $.path, G));
    }).filter((J) => !!J);
    if ($.common.async) return Promise.all(W).then((J) => {
      return I0.mergeArray(Q, J);
    });
    else return I0.mergeArray(Q, W);
  }
  get items() {
    return this._def.items;
  }
  rest(X) {
    return new _M1({ ...this._def, rest: X });
  }
};
M1.create = (X, Q) => {
  if (!Array.isArray(X)) throw Error("You must pass an array of schemas to z.tuple([ ... ])");
  return new M1({ items: X, typeName: j.ZodTuple, rest: null, ...l(Q) });
};
var M4 = class _M4 extends p {
  get keySchema() {
    return this._def.keyType;
  }
  get valueSchema() {
    return this._def.valueType;
  }
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X);
    if ($.parsedType !== E.object) return b($, { code: w.invalid_type, expected: E.object, received: $.parsedType }), g;
    let Y = [], W = this._def.keyType, J = this._def.valueType;
    for (let G in $.data) Y.push({ key: W._parse(new r0($, G, $.path, G)), value: J._parse(new r0($, $.data[G], $.path, G)), alwaysSet: G in $.data });
    if ($.common.async) return I0.mergeObjectAsync(Q, Y);
    else return I0.mergeObjectSync(Q, Y);
  }
  get element() {
    return this._def.valueType;
  }
  static create(X, Q, $) {
    if (Q instanceof p) return new _M4({ keyType: X, valueType: Q, typeName: j.ZodRecord, ...l($) });
    return new _M4({ keyType: A1.create(), valueType: X, typeName: j.ZodRecord, ...l(Q) });
  }
};
var j4 = class extends p {
  get keySchema() {
    return this._def.keyType;
  }
  get valueSchema() {
    return this._def.valueType;
  }
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X);
    if ($.parsedType !== E.map) return b($, { code: w.invalid_type, expected: E.map, received: $.parsedType }), g;
    let Y = this._def.keyType, W = this._def.valueType, J = [...$.data.entries()].map(([G, H], B) => {
      return { key: Y._parse(new r0($, G, $.path, [B, "key"])), value: W._parse(new r0($, H, $.path, [B, "value"])) };
    });
    if ($.common.async) {
      let G = /* @__PURE__ */ new Map();
      return Promise.resolve().then(async () => {
        for (let H of J) {
          let B = await H.key, z = await H.value;
          if (B.status === "aborted" || z.status === "aborted") return g;
          if (B.status === "dirty" || z.status === "dirty") Q.dirty();
          G.set(B.value, z.value);
        }
        return { status: Q.value, value: G };
      });
    } else {
      let G = /* @__PURE__ */ new Map();
      for (let H of J) {
        let { key: B, value: z } = H;
        if (B.status === "aborted" || z.status === "aborted") return g;
        if (B.status === "dirty" || z.status === "dirty") Q.dirty();
        G.set(B.value, z.value);
      }
      return { status: Q.value, value: G };
    }
  }
};
j4.create = (X, Q, $) => {
  return new j4({ valueType: Q, keyType: X, typeName: j.ZodMap, ...l($) });
};
var P6 = class _P6 extends p {
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X);
    if ($.parsedType !== E.set) return b($, { code: w.invalid_type, expected: E.set, received: $.parsedType }), g;
    let Y = this._def;
    if (Y.minSize !== null) {
      if ($.data.size < Y.minSize.value) b($, { code: w.too_small, minimum: Y.minSize.value, type: "set", inclusive: true, exact: false, message: Y.minSize.message }), Q.dirty();
    }
    if (Y.maxSize !== null) {
      if ($.data.size > Y.maxSize.value) b($, { code: w.too_big, maximum: Y.maxSize.value, type: "set", inclusive: true, exact: false, message: Y.maxSize.message }), Q.dirty();
    }
    let W = this._def.valueType;
    function J(H) {
      let B = /* @__PURE__ */ new Set();
      for (let z of H) {
        if (z.status === "aborted") return g;
        if (z.status === "dirty") Q.dirty();
        B.add(z.value);
      }
      return { status: Q.value, value: B };
    }
    let G = [...$.data.values()].map((H, B) => W._parse(new r0($, H, $.path, B)));
    if ($.common.async) return Promise.all(G).then((H) => J(H));
    else return J(G);
  }
  min(X, Q) {
    return new _P6({ ...this._def, minSize: { value: X, message: Z.toString(Q) } });
  }
  max(X, Q) {
    return new _P6({ ...this._def, maxSize: { value: X, message: Z.toString(Q) } });
  }
  size(X, Q) {
    return this.min(X, Q).max(X, Q);
  }
  nonempty(X) {
    return this.min(1, X);
  }
};
P6.create = (X, Q) => {
  return new P6({ valueType: X, minSize: null, maxSize: null, typeName: j.ZodSet, ...l(Q) });
};
var JX = class _JX extends p {
  constructor() {
    super(...arguments);
    this.validate = this.implement;
  }
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X);
    if (Q.parsedType !== E.function) return b(Q, { code: w.invalid_type, expected: E.function, received: Q.parsedType }), g;
    function $(G, H) {
      return N4({ data: G, path: Q.path, errorMaps: [Q.common.contextualErrorMap, Q.schemaErrorMap, YX(), v1].filter((B) => !!B), issueData: { code: w.invalid_arguments, argumentsError: H } });
    }
    function Y(G, H) {
      return N4({ data: G, path: Q.path, errorMaps: [Q.common.contextualErrorMap, Q.schemaErrorMap, YX(), v1].filter((B) => !!B), issueData: { code: w.invalid_return_type, returnTypeError: H } });
    }
    let W = { errorMap: Q.common.contextualErrorMap }, J = Q.data;
    if (this._def.returns instanceof S6) {
      let G = this;
      return C0(async function(...H) {
        let B = new f0([]), z = await G._def.args.parseAsync(H, W).catch((L) => {
          throw B.addIssue($(H, L)), B;
        }), K = await Reflect.apply(J, this, z);
        return await G._def.returns._def.type.parseAsync(K, W).catch((L) => {
          throw B.addIssue(Y(K, L)), B;
        });
      });
    } else {
      let G = this;
      return C0(function(...H) {
        let B = G._def.args.safeParse(H, W);
        if (!B.success) throw new f0([$(H, B.error)]);
        let z = Reflect.apply(J, this, B.data), K = G._def.returns.safeParse(z, W);
        if (!K.success) throw new f0([Y(z, K.error)]);
        return K.data;
      });
    }
  }
  parameters() {
    return this._def.args;
  }
  returnType() {
    return this._def.returns;
  }
  args(...X) {
    return new _JX({ ...this._def, args: M1.create(X).rest(t1.create()) });
  }
  returns(X) {
    return new _JX({ ...this._def, returns: X });
  }
  implement(X) {
    return this.parse(X);
  }
  strictImplement(X) {
    return this.parse(X);
  }
  static create(X, Q, $) {
    return new _JX({ args: X ? X : M1.create([]).rest(t1.create()), returns: Q || t1.create(), typeName: j.ZodFunction, ...l($) });
  }
};
var UX = class extends p {
  get schema() {
    return this._def.getter();
  }
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X);
    return this._def.getter()._parse({ data: Q.data, path: Q.path, parent: Q });
  }
};
UX.create = (X, Q) => {
  return new UX({ getter: X, typeName: j.ZodLazy, ...l(Q) });
};
var VX = class extends p {
  _parse(X) {
    if (X.data !== this._def.value) {
      let Q = this._getOrReturnCtx(X);
      return b(Q, { received: Q.data, code: w.invalid_literal, expected: this._def.value }), g;
    }
    return { status: "valid", value: X.data };
  }
  get value() {
    return this._def.value;
  }
};
VX.create = (X, Q) => {
  return new VX({ value: X, typeName: j.ZodLiteral, ...l(Q) });
};
function qW(X, Q) {
  return new a1({ values: X, typeName: j.ZodEnum, ...l(Q) });
}
var a1 = class _a1 extends p {
  _parse(X) {
    if (typeof X.data !== "string") {
      let Q = this._getOrReturnCtx(X), $ = this._def.values;
      return b(Q, { expected: n.joinValues($), received: Q.parsedType, code: w.invalid_type }), g;
    }
    if (!this._cache) this._cache = new Set(this._def.values);
    if (!this._cache.has(X.data)) {
      let Q = this._getOrReturnCtx(X), $ = this._def.values;
      return b(Q, { received: Q.data, code: w.invalid_enum_value, options: $ }), g;
    }
    return C0(X.data);
  }
  get options() {
    return this._def.values;
  }
  get enum() {
    let X = {};
    for (let Q of this._def.values) X[Q] = Q;
    return X;
  }
  get Values() {
    let X = {};
    for (let Q of this._def.values) X[Q] = Q;
    return X;
  }
  get Enum() {
    let X = {};
    for (let Q of this._def.values) X[Q] = Q;
    return X;
  }
  extract(X, Q = this._def) {
    return _a1.create(X, { ...this._def, ...Q });
  }
  exclude(X, Q = this._def) {
    return _a1.create(this.options.filter(($) => !X.includes($)), { ...this._def, ...Q });
  }
};
a1.create = qW;
var LX = class extends p {
  _parse(X) {
    let Q = n.getValidEnumValues(this._def.values), $ = this._getOrReturnCtx(X);
    if ($.parsedType !== E.string && $.parsedType !== E.number) {
      let Y = n.objectValues(Q);
      return b($, { expected: n.joinValues(Y), received: $.parsedType, code: w.invalid_type }), g;
    }
    if (!this._cache) this._cache = new Set(n.getValidEnumValues(this._def.values));
    if (!this._cache.has(X.data)) {
      let Y = n.objectValues(Q);
      return b($, { received: $.data, code: w.invalid_enum_value, options: Y }), g;
    }
    return C0(X.data);
  }
  get enum() {
    return this._def.values;
  }
};
LX.create = (X, Q) => {
  return new LX({ values: X, typeName: j.ZodNativeEnum, ...l(Q) });
};
var S6 = class extends p {
  unwrap() {
    return this._def.type;
  }
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X);
    if (Q.parsedType !== E.promise && Q.common.async === false) return b(Q, { code: w.invalid_type, expected: E.promise, received: Q.parsedType }), g;
    let $ = Q.parsedType === E.promise ? Q.data : Promise.resolve(Q.data);
    return C0($.then((Y) => {
      return this._def.type.parseAsync(Y, { path: Q.path, errorMap: Q.common.contextualErrorMap });
    }));
  }
};
S6.create = (X, Q) => {
  return new S6({ type: X, typeName: j.ZodPromise, ...l(Q) });
};
var H1 = class extends p {
  innerType() {
    return this._def.schema;
  }
  sourceType() {
    return this._def.schema._def.typeName === j.ZodEffects ? this._def.schema.sourceType() : this._def.schema;
  }
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X), Y = this._def.effect || null, W = { addIssue: (J) => {
      if (b($, J), J.fatal) Q.abort();
      else Q.dirty();
    }, get path() {
      return $.path;
    } };
    if (W.addIssue = W.addIssue.bind(W), Y.type === "preprocess") {
      let J = Y.transform($.data, W);
      if ($.common.async) return Promise.resolve(J).then(async (G) => {
        if (Q.value === "aborted") return g;
        let H = await this._def.schema._parseAsync({ data: G, path: $.path, parent: $ });
        if (H.status === "aborted") return g;
        if (H.status === "dirty") return R6(H.value);
        if (Q.value === "dirty") return R6(H.value);
        return H;
      });
      else {
        if (Q.value === "aborted") return g;
        let G = this._def.schema._parseSync({ data: J, path: $.path, parent: $ });
        if (G.status === "aborted") return g;
        if (G.status === "dirty") return R6(G.value);
        if (Q.value === "dirty") return R6(G.value);
        return G;
      }
    }
    if (Y.type === "refinement") {
      let J = (G) => {
        let H = Y.refinement(G, W);
        if ($.common.async) return Promise.resolve(H);
        if (H instanceof Promise) throw Error("Async refinement encountered during synchronous parse operation. Use .parseAsync instead.");
        return G;
      };
      if ($.common.async === false) {
        let G = this._def.schema._parseSync({ data: $.data, path: $.path, parent: $ });
        if (G.status === "aborted") return g;
        if (G.status === "dirty") Q.dirty();
        return J(G.value), { status: Q.value, value: G.value };
      } else return this._def.schema._parseAsync({ data: $.data, path: $.path, parent: $ }).then((G) => {
        if (G.status === "aborted") return g;
        if (G.status === "dirty") Q.dirty();
        return J(G.value).then(() => {
          return { status: Q.value, value: G.value };
        });
      });
    }
    if (Y.type === "transform") if ($.common.async === false) {
      let J = this._def.schema._parseSync({ data: $.data, path: $.path, parent: $ });
      if (!o1(J)) return g;
      let G = Y.transform(J.value, W);
      if (G instanceof Promise) throw Error("Asynchronous transform encountered during synchronous parse operation. Use .parseAsync instead.");
      return { status: Q.value, value: G };
    } else return this._def.schema._parseAsync({ data: $.data, path: $.path, parent: $ }).then((J) => {
      if (!o1(J)) return g;
      return Promise.resolve(Y.transform(J.value, W)).then((G) => ({ status: Q.value, value: G }));
    });
    n.assertNever(Y);
  }
};
H1.create = (X, Q, $) => {
  return new H1({ schema: X, typeName: j.ZodEffects, effect: Q, ...l($) });
};
H1.createWithPreprocess = (X, Q, $) => {
  return new H1({ schema: Q, effect: { type: "preprocess", transform: X }, typeName: j.ZodEffects, ...l($) });
};
var G1 = class extends p {
  _parse(X) {
    if (this._getType(X) === E.undefined) return C0(void 0);
    return this._def.innerType._parse(X);
  }
  unwrap() {
    return this._def.innerType;
  }
};
G1.create = (X, Q) => {
  return new G1({ innerType: X, typeName: j.ZodOptional, ...l(Q) });
};
var T1 = class extends p {
  _parse(X) {
    if (this._getType(X) === E.null) return C0(null);
    return this._def.innerType._parse(X);
  }
  unwrap() {
    return this._def.innerType;
  }
};
T1.create = (X, Q) => {
  return new T1({ innerType: X, typeName: j.ZodNullable, ...l(Q) });
};
var qX = class extends p {
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X), $ = Q.data;
    if (Q.parsedType === E.undefined) $ = this._def.defaultValue();
    return this._def.innerType._parse({ data: $, path: Q.path, parent: Q });
  }
  removeDefault() {
    return this._def.innerType;
  }
};
qX.create = (X, Q) => {
  return new qX({ innerType: X, typeName: j.ZodDefault, defaultValue: typeof Q.default === "function" ? Q.default : () => Q.default, ...l(Q) });
};
var FX = class extends p {
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X), $ = { ...Q, common: { ...Q.common, issues: [] } }, Y = this._def.innerType._parse({ data: $.data, path: $.path, parent: { ...$ } });
    if (WX(Y)) return Y.then((W) => {
      return { status: "valid", value: W.status === "valid" ? W.value : this._def.catchValue({ get error() {
        return new f0($.common.issues);
      }, input: $.data }) };
    });
    else return { status: "valid", value: Y.status === "valid" ? Y.value : this._def.catchValue({ get error() {
      return new f0($.common.issues);
    }, input: $.data }) };
  }
  removeCatch() {
    return this._def.innerType;
  }
};
FX.create = (X, Q) => {
  return new FX({ innerType: X, typeName: j.ZodCatch, catchValue: typeof Q.catch === "function" ? Q.catch : () => Q.catch, ...l(Q) });
};
var R4 = class extends p {
  _parse(X) {
    if (this._getType(X) !== E.nan) {
      let $ = this._getOrReturnCtx(X);
      return b($, { code: w.invalid_type, expected: E.nan, received: $.parsedType }), g;
    }
    return { status: "valid", value: X.data };
  }
};
R4.create = (X) => {
  return new R4({ typeName: j.ZodNaN, ...l(X) });
};
var H2 = Symbol("zod_brand");
var D8 = class extends p {
  _parse(X) {
    let { ctx: Q } = this._processInputParams(X), $ = Q.data;
    return this._def.type._parse({ data: $, path: Q.path, parent: Q });
  }
  unwrap() {
    return this._def.type;
  }
};
var E4 = class _E4 extends p {
  _parse(X) {
    let { status: Q, ctx: $ } = this._processInputParams(X);
    if ($.common.async) return (async () => {
      let W = await this._def.in._parseAsync({ data: $.data, path: $.path, parent: $ });
      if (W.status === "aborted") return g;
      if (W.status === "dirty") return Q.dirty(), R6(W.value);
      else return this._def.out._parseAsync({ data: W.value, path: $.path, parent: $ });
    })();
    else {
      let Y = this._def.in._parseSync({ data: $.data, path: $.path, parent: $ });
      if (Y.status === "aborted") return g;
      if (Y.status === "dirty") return Q.dirty(), { status: "dirty", value: Y.value };
      else return this._def.out._parseSync({ data: Y.value, path: $.path, parent: $ });
    }
  }
  static create(X, Q) {
    return new _E4({ in: X, out: Q, typeName: j.ZodPipeline });
  }
};
var NX = class extends p {
  _parse(X) {
    let Q = this._def.innerType._parse(X), $ = (Y) => {
      if (o1(Y)) Y.value = Object.freeze(Y.value);
      return Y;
    };
    return WX(Q) ? Q.then((Y) => $(Y)) : $(Q);
  }
  unwrap() {
    return this._def.innerType;
  }
};
NX.create = (X, Q) => {
  return new NX({ innerType: X, typeName: j.ZodReadonly, ...l(Q) });
};
var B2 = { object: V0.lazycreate };
var j;
(function(X) {
  X.ZodString = "ZodString", X.ZodNumber = "ZodNumber", X.ZodNaN = "ZodNaN", X.ZodBigInt = "ZodBigInt", X.ZodBoolean = "ZodBoolean", X.ZodDate = "ZodDate", X.ZodSymbol = "ZodSymbol", X.ZodUndefined = "ZodUndefined", X.ZodNull = "ZodNull", X.ZodAny = "ZodAny", X.ZodUnknown = "ZodUnknown", X.ZodNever = "ZodNever", X.ZodVoid = "ZodVoid", X.ZodArray = "ZodArray", X.ZodObject = "ZodObject", X.ZodUnion = "ZodUnion", X.ZodDiscriminatedUnion = "ZodDiscriminatedUnion", X.ZodIntersection = "ZodIntersection", X.ZodTuple = "ZodTuple", X.ZodRecord = "ZodRecord", X.ZodMap = "ZodMap", X.ZodSet = "ZodSet", X.ZodFunction = "ZodFunction", X.ZodLazy = "ZodLazy", X.ZodLiteral = "ZodLiteral", X.ZodEnum = "ZodEnum", X.ZodEffects = "ZodEffects", X.ZodNativeEnum = "ZodNativeEnum", X.ZodOptional = "ZodOptional", X.ZodNullable = "ZodNullable", X.ZodDefault = "ZodDefault", X.ZodCatch = "ZodCatch", X.ZodPromise = "ZodPromise", X.ZodBranded = "ZodBranded", X.ZodPipeline = "ZodPipeline", X.ZodReadonly = "ZodReadonly";
})(j || (j = {}));
var z2 = A1.create;
var K2 = I6.create;
var U2 = R4.create;
var V2 = b6.create;
var L2 = O4.create;
var q2 = GX.create;
var F2 = D4.create;
var N2 = HX.create;
var O2 = BX.create;
var D2 = A4.create;
var A2 = t1.create;
var w2 = w1.create;
var M2 = w4.create;
var j2 = J1.create;
var FW = V0.create;
var R2 = V0.strictCreate;
var E2 = zX.create;
var I2 = O8.create;
var b2 = KX.create;
var P2 = M1.create;
var S2 = M4.create;
var Z2 = j4.create;
var C2 = P6.create;
var k2 = JX.create;
var v2 = UX.create;
var T2 = VX.create;
var _2 = a1.create;
var x2 = LX.create;
var y2 = S6.create;
var g2 = H1.create;
var h2 = G1.create;
var f2 = T1.create;
var u2 = H1.createWithPreprocess;
var l2 = E4.create;
var wV = Object.freeze({ status: "aborted" });
function O(X, Q, $) {
  function Y(H, B) {
    var z;
    Object.defineProperty(H, "_zod", { value: H._zod ?? {}, enumerable: false }), (z = H._zod).traits ?? (z.traits = /* @__PURE__ */ new Set()), H._zod.traits.add(X), Q(H, B);
    for (let K in G.prototype) if (!(K in H)) Object.defineProperty(H, K, { value: G.prototype[K].bind(H) });
    H._zod.constr = G, H._zod.def = B;
  }
  let W = $?.Parent ?? Object;
  class J extends W {
  }
  Object.defineProperty(J, "name", { value: X });
  function G(H) {
    var B;
    let z = $?.Parent ? new J() : this;
    Y(z, H), (B = z._zod).deferred ?? (B.deferred = []);
    for (let K of z._zod.deferred) K();
    return z;
  }
  return Object.defineProperty(G, "init", { value: Y }), Object.defineProperty(G, Symbol.hasInstance, { value: (H) => {
    if ($?.Parent && H instanceof $.Parent) return true;
    return H?._zod?.traits?.has(X);
  } }), Object.defineProperty(G, "name", { value: X }), G;
}
var MV = Symbol("zod_brand");
var _1 = class extends Error {
  constructor() {
    super("Encountered Promise during synchronous parse. Use .parseAsync() instead.");
  }
};
var I4 = {};
function u0(X) {
  if (X) Object.assign(I4, X);
  return I4;
}
var i = {};
U7(i, { unwrapMessage: () => OX, stringifyPrimitive: () => S4, required: () => hV, randomString: () => ZV, propertyKeyTypes: () => E8, promiseAllObject: () => SV, primitiveTypes: () => NW, prefixIssues: () => B1, pick: () => TV, partial: () => gV, optionalKeys: () => I8, omit: () => _V, numKeys: () => CV, nullish: () => wX, normalizeParams: () => y, merge: () => yV, jsonStringifyReplacer: () => w8, joinValues: () => b4, issue: () => P8, isPlainObject: () => C6, isObject: () => Z6, getSizableOrigin: () => DW, getParsedType: () => kV, getLengthableOrigin: () => jX, getEnumValues: () => DX, getElementAtPath: () => PV, floatSafeRemainder: () => M8, finalizeIssue: () => o0, extend: () => xV, escapeRegex: () => x1, esc: () => s1, defineLazy: () => Y0, createTransparentProxy: () => vV, clone: () => l0, cleanRegex: () => MX, cleanEnum: () => fV, captureStackTrace: () => P4, cached: () => AX, assignProp: () => j8, assertNotEqual: () => RV, assertNever: () => IV, assertIs: () => EV, assertEqual: () => jV, assert: () => bV, allowsEval: () => R8, aborted: () => e1, NUMBER_FORMAT_RANGES: () => b8, Class: () => AW, BIGINT_FORMAT_RANGES: () => OW });
function jV(X) {
  return X;
}
function RV(X) {
  return X;
}
function EV(X) {
}
function IV(X) {
  throw Error();
}
function bV(X) {
}
function DX(X) {
  let Q = Object.values(X).filter((Y) => typeof Y === "number");
  return Object.entries(X).filter(([Y, W]) => Q.indexOf(+Y) === -1).map(([Y, W]) => W);
}
function b4(X, Q = "|") {
  return X.map(($) => S4($)).join(Q);
}
function w8(X, Q) {
  if (typeof Q === "bigint") return Q.toString();
  return Q;
}
function AX(X) {
  return { get value() {
    {
      let $ = X();
      return Object.defineProperty(this, "value", { value: $ }), $;
    }
    throw Error("cached value already set");
  } };
}
function wX(X) {
  return X === null || X === void 0;
}
function MX(X) {
  let Q = X.startsWith("^") ? 1 : 0, $ = X.endsWith("$") ? X.length - 1 : X.length;
  return X.slice(Q, $);
}
function M8(X, Q) {
  let $ = (X.toString().split(".")[1] || "").length, Y = (Q.toString().split(".")[1] || "").length, W = $ > Y ? $ : Y, J = Number.parseInt(X.toFixed(W).replace(".", "")), G = Number.parseInt(Q.toFixed(W).replace(".", ""));
  return J % G / 10 ** W;
}
function Y0(X, Q, $) {
  Object.defineProperty(X, Q, { get() {
    {
      let W = $();
      return X[Q] = W, W;
    }
    throw Error("cached value already set");
  }, set(W) {
    Object.defineProperty(X, Q, { value: W });
  }, configurable: true });
}
function j8(X, Q, $) {
  Object.defineProperty(X, Q, { value: $, writable: true, enumerable: true, configurable: true });
}
function PV(X, Q) {
  if (!Q) return X;
  return Q.reduce(($, Y) => $?.[Y], X);
}
function SV(X) {
  let Q = Object.keys(X), $ = Q.map((Y) => X[Y]);
  return Promise.all($).then((Y) => {
    let W = {};
    for (let J = 0; J < Q.length; J++) W[Q[J]] = Y[J];
    return W;
  });
}
function ZV(X = 10) {
  let $ = "";
  for (let Y = 0; Y < X; Y++) $ += "abcdefghijklmnopqrstuvwxyz"[Math.floor(Math.random() * 26)];
  return $;
}
function s1(X) {
  return JSON.stringify(X);
}
var P4 = Error.captureStackTrace ? Error.captureStackTrace : (...X) => {
};
function Z6(X) {
  return typeof X === "object" && X !== null && !Array.isArray(X);
}
var R8 = AX(() => {
  if (typeof navigator < "u" && navigator?.userAgent?.includes("Cloudflare")) return false;
  try {
    return new Function(""), true;
  } catch (X) {
    return false;
  }
});
function C6(X) {
  if (Z6(X) === false) return false;
  let Q = X.constructor;
  if (Q === void 0) return true;
  let $ = Q.prototype;
  if (Z6($) === false) return false;
  if (Object.prototype.hasOwnProperty.call($, "isPrototypeOf") === false) return false;
  return true;
}
function CV(X) {
  let Q = 0;
  for (let $ in X) if (Object.prototype.hasOwnProperty.call(X, $)) Q++;
  return Q;
}
var kV = (X) => {
  let Q = typeof X;
  switch (Q) {
    case "undefined":
      return "undefined";
    case "string":
      return "string";
    case "number":
      return Number.isNaN(X) ? "nan" : "number";
    case "boolean":
      return "boolean";
    case "function":
      return "function";
    case "bigint":
      return "bigint";
    case "symbol":
      return "symbol";
    case "object":
      if (Array.isArray(X)) return "array";
      if (X === null) return "null";
      if (X.then && typeof X.then === "function" && X.catch && typeof X.catch === "function") return "promise";
      if (typeof Map < "u" && X instanceof Map) return "map";
      if (typeof Set < "u" && X instanceof Set) return "set";
      if (typeof Date < "u" && X instanceof Date) return "date";
      if (typeof File < "u" && X instanceof File) return "file";
      return "object";
    default:
      throw Error(`Unknown data type: ${Q}`);
  }
};
var E8 = /* @__PURE__ */ new Set(["string", "number", "symbol"]);
var NW = /* @__PURE__ */ new Set(["string", "number", "bigint", "boolean", "symbol", "undefined"]);
function x1(X) {
  return X.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
function l0(X, Q, $) {
  let Y = new X._zod.constr(Q ?? X._zod.def);
  if (!Q || $?.parent) Y._zod.parent = X;
  return Y;
}
function y(X) {
  let Q = X;
  if (!Q) return {};
  if (typeof Q === "string") return { error: () => Q };
  if (Q?.message !== void 0) {
    if (Q?.error !== void 0) throw Error("Cannot specify both `message` and `error` params");
    Q.error = Q.message;
  }
  if (delete Q.message, typeof Q.error === "string") return { ...Q, error: () => Q.error };
  return Q;
}
function vV(X) {
  let Q;
  return new Proxy({}, { get($, Y, W) {
    return Q ?? (Q = X()), Reflect.get(Q, Y, W);
  }, set($, Y, W, J) {
    return Q ?? (Q = X()), Reflect.set(Q, Y, W, J);
  }, has($, Y) {
    return Q ?? (Q = X()), Reflect.has(Q, Y);
  }, deleteProperty($, Y) {
    return Q ?? (Q = X()), Reflect.deleteProperty(Q, Y);
  }, ownKeys($) {
    return Q ?? (Q = X()), Reflect.ownKeys(Q);
  }, getOwnPropertyDescriptor($, Y) {
    return Q ?? (Q = X()), Reflect.getOwnPropertyDescriptor(Q, Y);
  }, defineProperty($, Y, W) {
    return Q ?? (Q = X()), Reflect.defineProperty(Q, Y, W);
  } });
}
function S4(X) {
  if (typeof X === "bigint") return X.toString() + "n";
  if (typeof X === "string") return `"${X}"`;
  return `${X}`;
}
function I8(X) {
  return Object.keys(X).filter((Q) => {
    return X[Q]._zod.optin === "optional" && X[Q]._zod.optout === "optional";
  });
}
var b8 = { safeint: [Number.MIN_SAFE_INTEGER, Number.MAX_SAFE_INTEGER], int32: [-2147483648, 2147483647], uint32: [0, 4294967295], float32: [-34028234663852886e22, 34028234663852886e22], float64: [-Number.MAX_VALUE, Number.MAX_VALUE] };
var OW = { int64: [BigInt("-9223372036854775808"), BigInt("9223372036854775807")], uint64: [BigInt(0), BigInt("18446744073709551615")] };
function TV(X, Q) {
  let $ = {}, Y = X._zod.def;
  for (let W in Q) {
    if (!(W in Y.shape)) throw Error(`Unrecognized key: "${W}"`);
    if (!Q[W]) continue;
    $[W] = Y.shape[W];
  }
  return l0(X, { ...X._zod.def, shape: $, checks: [] });
}
function _V(X, Q) {
  let $ = { ...X._zod.def.shape }, Y = X._zod.def;
  for (let W in Q) {
    if (!(W in Y.shape)) throw Error(`Unrecognized key: "${W}"`);
    if (!Q[W]) continue;
    delete $[W];
  }
  return l0(X, { ...X._zod.def, shape: $, checks: [] });
}
function xV(X, Q) {
  if (!C6(Q)) throw Error("Invalid input to extend: expected a plain object");
  let $ = { ...X._zod.def, get shape() {
    let Y = { ...X._zod.def.shape, ...Q };
    return j8(this, "shape", Y), Y;
  }, checks: [] };
  return l0(X, $);
}
function yV(X, Q) {
  return l0(X, { ...X._zod.def, get shape() {
    let $ = { ...X._zod.def.shape, ...Q._zod.def.shape };
    return j8(this, "shape", $), $;
  }, catchall: Q._zod.def.catchall, checks: [] });
}
function gV(X, Q, $) {
  let Y = Q._zod.def.shape, W = { ...Y };
  if ($) for (let J in $) {
    if (!(J in Y)) throw Error(`Unrecognized key: "${J}"`);
    if (!$[J]) continue;
    W[J] = X ? new X({ type: "optional", innerType: Y[J] }) : Y[J];
  }
  else for (let J in Y) W[J] = X ? new X({ type: "optional", innerType: Y[J] }) : Y[J];
  return l0(Q, { ...Q._zod.def, shape: W, checks: [] });
}
function hV(X, Q, $) {
  let Y = Q._zod.def.shape, W = { ...Y };
  if ($) for (let J in $) {
    if (!(J in W)) throw Error(`Unrecognized key: "${J}"`);
    if (!$[J]) continue;
    W[J] = new X({ type: "nonoptional", innerType: Y[J] });
  }
  else for (let J in Y) W[J] = new X({ type: "nonoptional", innerType: Y[J] });
  return l0(Q, { ...Q._zod.def, shape: W, checks: [] });
}
function e1(X, Q = 0) {
  for (let $ = Q; $ < X.issues.length; $++) if (X.issues[$]?.continue !== true) return true;
  return false;
}
function B1(X, Q) {
  return Q.map(($) => {
    var Y;
    return (Y = $).path ?? (Y.path = []), $.path.unshift(X), $;
  });
}
function OX(X) {
  return typeof X === "string" ? X : X?.message;
}
function o0(X, Q, $) {
  let Y = { ...X, path: X.path ?? [] };
  if (!X.message) {
    let W = OX(X.inst?._zod.def?.error?.(X)) ?? OX(Q?.error?.(X)) ?? OX($.customError?.(X)) ?? OX($.localeError?.(X)) ?? "Invalid input";
    Y.message = W;
  }
  if (delete Y.inst, delete Y.continue, !Q?.reportInput) delete Y.input;
  return Y;
}
function DW(X) {
  if (X instanceof Set) return "set";
  if (X instanceof Map) return "map";
  if (X instanceof File) return "file";
  return "unknown";
}
function jX(X) {
  if (Array.isArray(X)) return "array";
  if (typeof X === "string") return "string";
  return "unknown";
}
function P8(...X) {
  let [Q, $, Y] = X;
  if (typeof Q === "string") return { message: Q, code: "custom", input: $, inst: Y };
  return { ...Q };
}
function fV(X) {
  return Object.entries(X).filter(([Q, $]) => {
    return Number.isNaN(Number.parseInt(Q, 10));
  }).map((Q) => Q[1]);
}
var AW = class {
  constructor(...X) {
  }
};
var wW = (X, Q) => {
  X.name = "$ZodError", Object.defineProperty(X, "_zod", { value: X._zod, enumerable: false }), Object.defineProperty(X, "issues", { value: Q, enumerable: false }), Object.defineProperty(X, "message", { get() {
    return JSON.stringify(Q, w8, 2);
  }, enumerable: true });
};
var Z4 = O("$ZodError", wW);
var RX = O("$ZodError", wW, { Parent: Error });
function S8(X, Q = ($) => $.message) {
  let $ = {}, Y = [];
  for (let W of X.issues) if (W.path.length > 0) $[W.path[0]] = $[W.path[0]] || [], $[W.path[0]].push(Q(W));
  else Y.push(Q(W));
  return { formErrors: Y, fieldErrors: $ };
}
function Z8(X, Q) {
  let $ = Q || function(J) {
    return J.message;
  }, Y = { _errors: [] }, W = (J) => {
    for (let G of J.issues) if (G.code === "invalid_union" && G.errors.length) G.errors.map((H) => W({ issues: H }));
    else if (G.code === "invalid_key") W({ issues: G.issues });
    else if (G.code === "invalid_element") W({ issues: G.issues });
    else if (G.path.length === 0) Y._errors.push($(G));
    else {
      let H = Y, B = 0;
      while (B < G.path.length) {
        let z = G.path[B];
        if (B !== G.path.length - 1) H[z] = H[z] || { _errors: [] };
        else H[z] = H[z] || { _errors: [] }, H[z]._errors.push($(G));
        H = H[z], B++;
      }
    }
  };
  return W(X), Y;
}
var C8 = (X) => (Q, $, Y, W) => {
  let J = Y ? Object.assign(Y, { async: false }) : { async: false }, G = Q._zod.run({ value: $, issues: [] }, J);
  if (G instanceof Promise) throw new _1();
  if (G.issues.length) {
    let H = new (W?.Err ?? X)(G.issues.map((B) => o0(B, J, u0())));
    throw P4(H, W?.callee), H;
  }
  return G.value;
};
var k8 = C8(RX);
var v8 = (X) => async (Q, $, Y, W) => {
  let J = Y ? Object.assign(Y, { async: true }) : { async: true }, G = Q._zod.run({ value: $, issues: [] }, J);
  if (G instanceof Promise) G = await G;
  if (G.issues.length) {
    let H = new (W?.Err ?? X)(G.issues.map((B) => o0(B, J, u0())));
    throw P4(H, W?.callee), H;
  }
  return G.value;
};
var T8 = v8(RX);
var _8 = (X) => (Q, $, Y) => {
  let W = Y ? { ...Y, async: false } : { async: false }, J = Q._zod.run({ value: $, issues: [] }, W);
  if (J instanceof Promise) throw new _1();
  return J.issues.length ? { success: false, error: new (X ?? Z4)(J.issues.map((G) => o0(G, W, u0()))) } : { success: true, data: J.value };
};
var X6 = _8(RX);
var x8 = (X) => async (Q, $, Y) => {
  let W = Y ? Object.assign(Y, { async: true }) : { async: true }, J = Q._zod.run({ value: $, issues: [] }, W);
  if (J instanceof Promise) J = await J;
  return J.issues.length ? { success: false, error: new X(J.issues.map((G) => o0(G, W, u0()))) } : { success: true, data: J.value };
};
var Q6 = x8(RX);
var MW = /^[cC][^\s-]{8,}$/;
var jW = /^[0-9a-z]+$/;
var RW = /^[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{26}$/;
var EW = /^[0-9a-vA-V]{20}$/;
var IW = /^[A-Za-z0-9]{27}$/;
var bW = /^[a-zA-Z0-9_-]{21}$/;
var PW = /^P(?:(\d+W)|(?!.*W)(?=\d|T\d)(\d+Y)?(\d+M)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+([.,]\d+)?S)?)?)$/;
var SW = /^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$/;
var y8 = (X) => {
  if (!X) return /^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000)$/;
  return new RegExp(`^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-${X}[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12})$`);
};
var ZW = /^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$/;
function CW() {
  return new RegExp("^(\\p{Extended_Pictographic}|\\p{Emoji_Component})+$", "u");
}
var kW = /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$/;
var vW = /^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|::|([0-9a-fA-F]{1,4})?::([0-9a-fA-F]{1,4}:?){0,6})$/;
var TW = /^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\/([0-9]|[1-2][0-9]|3[0-2])$/;
var _W = /^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|::|([0-9a-fA-F]{1,4})?::([0-9a-fA-F]{1,4}:?){0,6})\/(12[0-8]|1[01][0-9]|[1-9]?[0-9])$/;
var xW = /^$|^(?:[0-9a-zA-Z+/]{4})*(?:(?:[0-9a-zA-Z+/]{2}==)|(?:[0-9a-zA-Z+/]{3}=))?$/;
var g8 = /^[A-Za-z0-9_-]*$/;
var yW = /^([a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$/;
var gW = /^\+(?:[0-9]){6,14}[0-9]$/;
var hW = "(?:(?:\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\\d|30)|(?:02)-(?:0[1-9]|1\\d|2[0-8])))";
var fW = new RegExp(`^${hW}$`);
function uW(X) {
  return typeof X.precision === "number" ? X.precision === -1 ? "(?:[01]\\d|2[0-3]):[0-5]\\d" : X.precision === 0 ? "(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d" : `(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d\\.\\d{${X.precision}}` : "(?:[01]\\d|2[0-3]):[0-5]\\d(?::[0-5]\\d(?:\\.\\d+)?)?";
}
function lW(X) {
  return new RegExp(`^${uW(X)}$`);
}
function mW(X) {
  let Q = uW({ precision: X.precision }), $ = ["Z"];
  if (X.local) $.push("");
  if (X.offset) $.push("([+-]\\d{2}:\\d{2})");
  let Y = `${Q}(?:${$.join("|")})`;
  return new RegExp(`^${hW}T(?:${Y})$`);
}
var cW = (X) => {
  let Q = X ? `[\\s\\S]{${X?.minimum ?? 0},${X?.maximum ?? ""}}` : "[\\s\\S]*";
  return new RegExp(`^${Q}$`);
};
var pW = /^\d+$/;
var dW = /^-?\d+(?:\.\d+)?/i;
var iW = /true|false/i;
var nW = /null/i;
var rW = /^[^A-Z]*$/;
var oW = /^[^a-z]*$/;
var w0 = O("$ZodCheck", (X, Q) => {
  var $;
  X._zod ?? (X._zod = {}), X._zod.def = Q, ($ = X._zod).onattach ?? ($.onattach = []);
});
var tW = { number: "number", bigint: "bigint", object: "date" };
var h8 = O("$ZodCheckLessThan", (X, Q) => {
  w0.init(X, Q);
  let $ = tW[typeof Q.value];
  X._zod.onattach.push((Y) => {
    let W = Y._zod.bag, J = (Q.inclusive ? W.maximum : W.exclusiveMaximum) ?? Number.POSITIVE_INFINITY;
    if (Q.value < J) if (Q.inclusive) W.maximum = Q.value;
    else W.exclusiveMaximum = Q.value;
  }), X._zod.check = (Y) => {
    if (Q.inclusive ? Y.value <= Q.value : Y.value < Q.value) return;
    Y.issues.push({ origin: $, code: "too_big", maximum: Q.value, input: Y.value, inclusive: Q.inclusive, inst: X, continue: !Q.abort });
  };
});
var f8 = O("$ZodCheckGreaterThan", (X, Q) => {
  w0.init(X, Q);
  let $ = tW[typeof Q.value];
  X._zod.onattach.push((Y) => {
    let W = Y._zod.bag, J = (Q.inclusive ? W.minimum : W.exclusiveMinimum) ?? Number.NEGATIVE_INFINITY;
    if (Q.value > J) if (Q.inclusive) W.minimum = Q.value;
    else W.exclusiveMinimum = Q.value;
  }), X._zod.check = (Y) => {
    if (Q.inclusive ? Y.value >= Q.value : Y.value > Q.value) return;
    Y.issues.push({ origin: $, code: "too_small", minimum: Q.value, input: Y.value, inclusive: Q.inclusive, inst: X, continue: !Q.abort });
  };
});
var aW = O("$ZodCheckMultipleOf", (X, Q) => {
  w0.init(X, Q), X._zod.onattach.push(($) => {
    var Y;
    (Y = $._zod.bag).multipleOf ?? (Y.multipleOf = Q.value);
  }), X._zod.check = ($) => {
    if (typeof $.value !== typeof Q.value) throw Error("Cannot mix number and bigint in multiple_of check.");
    if (typeof $.value === "bigint" ? $.value % Q.value === BigInt(0) : M8($.value, Q.value) === 0) return;
    $.issues.push({ origin: typeof $.value, code: "not_multiple_of", divisor: Q.value, input: $.value, inst: X, continue: !Q.abort });
  };
});
var sW = O("$ZodCheckNumberFormat", (X, Q) => {
  w0.init(X, Q), Q.format = Q.format || "float64";
  let $ = Q.format?.includes("int"), Y = $ ? "int" : "number", [W, J] = b8[Q.format];
  X._zod.onattach.push((G) => {
    let H = G._zod.bag;
    if (H.format = Q.format, H.minimum = W, H.maximum = J, $) H.pattern = pW;
  }), X._zod.check = (G) => {
    let H = G.value;
    if ($) {
      if (!Number.isInteger(H)) {
        G.issues.push({ expected: Y, format: Q.format, code: "invalid_type", input: H, inst: X });
        return;
      }
      if (!Number.isSafeInteger(H)) {
        if (H > 0) G.issues.push({ input: H, code: "too_big", maximum: Number.MAX_SAFE_INTEGER, note: "Integers must be within the safe integer range.", inst: X, origin: Y, continue: !Q.abort });
        else G.issues.push({ input: H, code: "too_small", minimum: Number.MIN_SAFE_INTEGER, note: "Integers must be within the safe integer range.", inst: X, origin: Y, continue: !Q.abort });
        return;
      }
    }
    if (H < W) G.issues.push({ origin: "number", input: H, code: "too_small", minimum: W, inclusive: true, inst: X, continue: !Q.abort });
    if (H > J) G.issues.push({ origin: "number", input: H, code: "too_big", maximum: J, inst: X });
  };
});
var eW = O("$ZodCheckMaxLength", (X, Q) => {
  w0.init(X, Q), X._zod.when = ($) => {
    let Y = $.value;
    return !wX(Y) && Y.length !== void 0;
  }, X._zod.onattach.push(($) => {
    let Y = $._zod.bag.maximum ?? Number.POSITIVE_INFINITY;
    if (Q.maximum < Y) $._zod.bag.maximum = Q.maximum;
  }), X._zod.check = ($) => {
    let Y = $.value;
    if (Y.length <= Q.maximum) return;
    let J = jX(Y);
    $.issues.push({ origin: J, code: "too_big", maximum: Q.maximum, inclusive: true, input: Y, inst: X, continue: !Q.abort });
  };
});
var XJ = O("$ZodCheckMinLength", (X, Q) => {
  w0.init(X, Q), X._zod.when = ($) => {
    let Y = $.value;
    return !wX(Y) && Y.length !== void 0;
  }, X._zod.onattach.push(($) => {
    let Y = $._zod.bag.minimum ?? Number.NEGATIVE_INFINITY;
    if (Q.minimum > Y) $._zod.bag.minimum = Q.minimum;
  }), X._zod.check = ($) => {
    let Y = $.value;
    if (Y.length >= Q.minimum) return;
    let J = jX(Y);
    $.issues.push({ origin: J, code: "too_small", minimum: Q.minimum, inclusive: true, input: Y, inst: X, continue: !Q.abort });
  };
});
var QJ = O("$ZodCheckLengthEquals", (X, Q) => {
  w0.init(X, Q), X._zod.when = ($) => {
    let Y = $.value;
    return !wX(Y) && Y.length !== void 0;
  }, X._zod.onattach.push(($) => {
    let Y = $._zod.bag;
    Y.minimum = Q.length, Y.maximum = Q.length, Y.length = Q.length;
  }), X._zod.check = ($) => {
    let Y = $.value, W = Y.length;
    if (W === Q.length) return;
    let J = jX(Y), G = W > Q.length;
    $.issues.push({ origin: J, ...G ? { code: "too_big", maximum: Q.length } : { code: "too_small", minimum: Q.length }, inclusive: true, exact: true, input: $.value, inst: X, continue: !Q.abort });
  };
});
var EX = O("$ZodCheckStringFormat", (X, Q) => {
  var $, Y;
  if (w0.init(X, Q), X._zod.onattach.push((W) => {
    let J = W._zod.bag;
    if (J.format = Q.format, Q.pattern) J.patterns ?? (J.patterns = /* @__PURE__ */ new Set()), J.patterns.add(Q.pattern);
  }), Q.pattern) ($ = X._zod).check ?? ($.check = (W) => {
    if (Q.pattern.lastIndex = 0, Q.pattern.test(W.value)) return;
    W.issues.push({ origin: "string", code: "invalid_format", format: Q.format, input: W.value, ...Q.pattern ? { pattern: Q.pattern.toString() } : {}, inst: X, continue: !Q.abort });
  });
  else (Y = X._zod).check ?? (Y.check = () => {
  });
});
var $J = O("$ZodCheckRegex", (X, Q) => {
  EX.init(X, Q), X._zod.check = ($) => {
    if (Q.pattern.lastIndex = 0, Q.pattern.test($.value)) return;
    $.issues.push({ origin: "string", code: "invalid_format", format: "regex", input: $.value, pattern: Q.pattern.toString(), inst: X, continue: !Q.abort });
  };
});
var YJ = O("$ZodCheckLowerCase", (X, Q) => {
  Q.pattern ?? (Q.pattern = rW), EX.init(X, Q);
});
var WJ = O("$ZodCheckUpperCase", (X, Q) => {
  Q.pattern ?? (Q.pattern = oW), EX.init(X, Q);
});
var JJ = O("$ZodCheckIncludes", (X, Q) => {
  w0.init(X, Q);
  let $ = x1(Q.includes), Y = new RegExp(typeof Q.position === "number" ? `^.{${Q.position}}${$}` : $);
  Q.pattern = Y, X._zod.onattach.push((W) => {
    let J = W._zod.bag;
    J.patterns ?? (J.patterns = /* @__PURE__ */ new Set()), J.patterns.add(Y);
  }), X._zod.check = (W) => {
    if (W.value.includes(Q.includes, Q.position)) return;
    W.issues.push({ origin: "string", code: "invalid_format", format: "includes", includes: Q.includes, input: W.value, inst: X, continue: !Q.abort });
  };
});
var GJ = O("$ZodCheckStartsWith", (X, Q) => {
  w0.init(X, Q);
  let $ = new RegExp(`^${x1(Q.prefix)}.*`);
  Q.pattern ?? (Q.pattern = $), X._zod.onattach.push((Y) => {
    let W = Y._zod.bag;
    W.patterns ?? (W.patterns = /* @__PURE__ */ new Set()), W.patterns.add($);
  }), X._zod.check = (Y) => {
    if (Y.value.startsWith(Q.prefix)) return;
    Y.issues.push({ origin: "string", code: "invalid_format", format: "starts_with", prefix: Q.prefix, input: Y.value, inst: X, continue: !Q.abort });
  };
});
var HJ = O("$ZodCheckEndsWith", (X, Q) => {
  w0.init(X, Q);
  let $ = new RegExp(`.*${x1(Q.suffix)}$`);
  Q.pattern ?? (Q.pattern = $), X._zod.onattach.push((Y) => {
    let W = Y._zod.bag;
    W.patterns ?? (W.patterns = /* @__PURE__ */ new Set()), W.patterns.add($);
  }), X._zod.check = (Y) => {
    if (Y.value.endsWith(Q.suffix)) return;
    Y.issues.push({ origin: "string", code: "invalid_format", format: "ends_with", suffix: Q.suffix, input: Y.value, inst: X, continue: !Q.abort });
  };
});
var BJ = O("$ZodCheckOverwrite", (X, Q) => {
  w0.init(X, Q), X._zod.check = ($) => {
    $.value = Q.tx($.value);
  };
});
var u8 = class {
  constructor(X = []) {
    if (this.content = [], this.indent = 0, this) this.args = X;
  }
  indented(X) {
    this.indent += 1, X(this), this.indent -= 1;
  }
  write(X) {
    if (typeof X === "function") {
      X(this, { execution: "sync" }), X(this, { execution: "async" });
      return;
    }
    let $ = X.split(`
`).filter((J) => J), Y = Math.min(...$.map((J) => J.length - J.trimStart().length)), W = $.map((J) => J.slice(Y)).map((J) => " ".repeat(this.indent * 2) + J);
    for (let J of W) this.content.push(J);
  }
  compile() {
    let X = Function, Q = this?.args, Y = [...(this?.content ?? [""]).map((W) => `  ${W}`)];
    return new X(...Q, Y.join(`
`));
  }
};
var KJ = { major: 4, minor: 0, patch: 0 };
var X0 = O("$ZodType", (X, Q) => {
  var $;
  X ?? (X = {}), X._zod.def = Q, X._zod.bag = X._zod.bag || {}, X._zod.version = KJ;
  let Y = [...X._zod.def.checks ?? []];
  if (X._zod.traits.has("$ZodCheck")) Y.unshift(X);
  for (let W of Y) for (let J of W._zod.onattach) J(X);
  if (Y.length === 0) ($ = X._zod).deferred ?? ($.deferred = []), X._zod.deferred?.push(() => {
    X._zod.run = X._zod.parse;
  });
  else {
    let W = (J, G, H) => {
      let B = e1(J), z;
      for (let K of G) {
        if (K._zod.when) {
          if (!K._zod.when(J)) continue;
        } else if (B) continue;
        let V = J.issues.length, L = K._zod.check(J);
        if (L instanceof Promise && H?.async === false) throw new _1();
        if (z || L instanceof Promise) z = (z ?? Promise.resolve()).then(async () => {
          if (await L, J.issues.length === V) return;
          if (!B) B = e1(J, V);
        });
        else {
          if (J.issues.length === V) continue;
          if (!B) B = e1(J, V);
        }
      }
      if (z) return z.then(() => {
        return J;
      });
      return J;
    };
    X._zod.run = (J, G) => {
      let H = X._zod.parse(J, G);
      if (H instanceof Promise) {
        if (G.async === false) throw new _1();
        return H.then((B) => W(B, Y, G));
      }
      return W(H, Y, G);
    };
  }
  X["~standard"] = { validate: (W) => {
    try {
      let J = X6(X, W);
      return J.success ? { value: J.data } : { issues: J.error?.issues };
    } catch (J) {
      return Q6(X, W).then((G) => G.success ? { value: G.data } : { issues: G.error?.issues });
    }
  }, vendor: "zod", version: 1 };
});
var IX = O("$ZodString", (X, Q) => {
  X0.init(X, Q), X._zod.pattern = [...X?._zod.bag?.patterns ?? []].pop() ?? cW(X._zod.bag), X._zod.parse = ($, Y) => {
    if (Q.coerce) try {
      $.value = String($.value);
    } catch (W) {
    }
    if (typeof $.value === "string") return $;
    return $.issues.push({ expected: "string", code: "invalid_type", input: $.value, inst: X }), $;
  };
});
var W0 = O("$ZodStringFormat", (X, Q) => {
  EX.init(X, Q), IX.init(X, Q);
});
var m8 = O("$ZodGUID", (X, Q) => {
  Q.pattern ?? (Q.pattern = SW), W0.init(X, Q);
});
var c8 = O("$ZodUUID", (X, Q) => {
  if (Q.version) {
    let Y = { v1: 1, v2: 2, v3: 3, v4: 4, v5: 5, v6: 6, v7: 7, v8: 8 }[Q.version];
    if (Y === void 0) throw Error(`Invalid UUID version: "${Q.version}"`);
    Q.pattern ?? (Q.pattern = y8(Y));
  } else Q.pattern ?? (Q.pattern = y8());
  W0.init(X, Q);
});
var p8 = O("$ZodEmail", (X, Q) => {
  Q.pattern ?? (Q.pattern = ZW), W0.init(X, Q);
});
var d8 = O("$ZodURL", (X, Q) => {
  W0.init(X, Q), X._zod.check = ($) => {
    try {
      let Y = $.value, W = new URL(Y), J = W.href;
      if (Q.hostname) {
        if (Q.hostname.lastIndex = 0, !Q.hostname.test(W.hostname)) $.issues.push({ code: "invalid_format", format: "url", note: "Invalid hostname", pattern: yW.source, input: $.value, inst: X, continue: !Q.abort });
      }
      if (Q.protocol) {
        if (Q.protocol.lastIndex = 0, !Q.protocol.test(W.protocol.endsWith(":") ? W.protocol.slice(0, -1) : W.protocol)) $.issues.push({ code: "invalid_format", format: "url", note: "Invalid protocol", pattern: Q.protocol.source, input: $.value, inst: X, continue: !Q.abort });
      }
      if (!Y.endsWith("/") && J.endsWith("/")) $.value = J.slice(0, -1);
      else $.value = J;
      return;
    } catch (Y) {
      $.issues.push({ code: "invalid_format", format: "url", input: $.value, inst: X, continue: !Q.abort });
    }
  };
});
var i8 = O("$ZodEmoji", (X, Q) => {
  Q.pattern ?? (Q.pattern = CW()), W0.init(X, Q);
});
var n8 = O("$ZodNanoID", (X, Q) => {
  Q.pattern ?? (Q.pattern = bW), W0.init(X, Q);
});
var r8 = O("$ZodCUID", (X, Q) => {
  Q.pattern ?? (Q.pattern = MW), W0.init(X, Q);
});
var o8 = O("$ZodCUID2", (X, Q) => {
  Q.pattern ?? (Q.pattern = jW), W0.init(X, Q);
});
var t8 = O("$ZodULID", (X, Q) => {
  Q.pattern ?? (Q.pattern = RW), W0.init(X, Q);
});
var a8 = O("$ZodXID", (X, Q) => {
  Q.pattern ?? (Q.pattern = EW), W0.init(X, Q);
});
var s8 = O("$ZodKSUID", (X, Q) => {
  Q.pattern ?? (Q.pattern = IW), W0.init(X, Q);
});
var wJ = O("$ZodISODateTime", (X, Q) => {
  Q.pattern ?? (Q.pattern = mW(Q)), W0.init(X, Q);
});
var MJ = O("$ZodISODate", (X, Q) => {
  Q.pattern ?? (Q.pattern = fW), W0.init(X, Q);
});
var jJ = O("$ZodISOTime", (X, Q) => {
  Q.pattern ?? (Q.pattern = lW(Q)), W0.init(X, Q);
});
var RJ = O("$ZodISODuration", (X, Q) => {
  Q.pattern ?? (Q.pattern = PW), W0.init(X, Q);
});
var e8 = O("$ZodIPv4", (X, Q) => {
  Q.pattern ?? (Q.pattern = kW), W0.init(X, Q), X._zod.onattach.push(($) => {
    let Y = $._zod.bag;
    Y.format = "ipv4";
  });
});
var XQ = O("$ZodIPv6", (X, Q) => {
  Q.pattern ?? (Q.pattern = vW), W0.init(X, Q), X._zod.onattach.push(($) => {
    let Y = $._zod.bag;
    Y.format = "ipv6";
  }), X._zod.check = ($) => {
    try {
      new URL(`http://[${$.value}]`);
    } catch {
      $.issues.push({ code: "invalid_format", format: "ipv6", input: $.value, inst: X, continue: !Q.abort });
    }
  };
});
var QQ = O("$ZodCIDRv4", (X, Q) => {
  Q.pattern ?? (Q.pattern = TW), W0.init(X, Q);
});
var $Q = O("$ZodCIDRv6", (X, Q) => {
  Q.pattern ?? (Q.pattern = _W), W0.init(X, Q), X._zod.check = ($) => {
    let [Y, W] = $.value.split("/");
    try {
      if (!W) throw Error();
      let J = Number(W);
      if (`${J}` !== W) throw Error();
      if (J < 0 || J > 128) throw Error();
      new URL(`http://[${Y}]`);
    } catch {
      $.issues.push({ code: "invalid_format", format: "cidrv6", input: $.value, inst: X, continue: !Q.abort });
    }
  };
});
function EJ(X) {
  if (X === "") return true;
  if (X.length % 4 !== 0) return false;
  try {
    return atob(X), true;
  } catch {
    return false;
  }
}
var YQ = O("$ZodBase64", (X, Q) => {
  Q.pattern ?? (Q.pattern = xW), W0.init(X, Q), X._zod.onattach.push(($) => {
    $._zod.bag.contentEncoding = "base64";
  }), X._zod.check = ($) => {
    if (EJ($.value)) return;
    $.issues.push({ code: "invalid_format", format: "base64", input: $.value, inst: X, continue: !Q.abort });
  };
});
function lV(X) {
  if (!g8.test(X)) return false;
  let Q = X.replace(/[-_]/g, (Y) => Y === "-" ? "+" : "/"), $ = Q.padEnd(Math.ceil(Q.length / 4) * 4, "=");
  return EJ($);
}
var WQ = O("$ZodBase64URL", (X, Q) => {
  Q.pattern ?? (Q.pattern = g8), W0.init(X, Q), X._zod.onattach.push(($) => {
    $._zod.bag.contentEncoding = "base64url";
  }), X._zod.check = ($) => {
    if (lV($.value)) return;
    $.issues.push({ code: "invalid_format", format: "base64url", input: $.value, inst: X, continue: !Q.abort });
  };
});
var JQ = O("$ZodE164", (X, Q) => {
  Q.pattern ?? (Q.pattern = gW), W0.init(X, Q);
});
function mV(X, Q = null) {
  try {
    let $ = X.split(".");
    if ($.length !== 3) return false;
    let [Y] = $;
    if (!Y) return false;
    let W = JSON.parse(atob(Y));
    if ("typ" in W && W?.typ !== "JWT") return false;
    if (!W.alg) return false;
    if (Q && (!("alg" in W) || W.alg !== Q)) return false;
    return true;
  } catch {
    return false;
  }
}
var GQ = O("$ZodJWT", (X, Q) => {
  W0.init(X, Q), X._zod.check = ($) => {
    if (mV($.value, Q.alg)) return;
    $.issues.push({ code: "invalid_format", format: "jwt", input: $.value, inst: X, continue: !Q.abort });
  };
});
var v42 = O("$ZodNumber", (X, Q) => {
  X0.init(X, Q), X._zod.pattern = X._zod.bag.pattern ?? dW, X._zod.parse = ($, Y) => {
    if (Q.coerce) try {
      $.value = Number($.value);
    } catch (G) {
    }
    let W = $.value;
    if (typeof W === "number" && !Number.isNaN(W) && Number.isFinite(W)) return $;
    let J = typeof W === "number" ? Number.isNaN(W) ? "NaN" : !Number.isFinite(W) ? "Infinity" : void 0 : void 0;
    return $.issues.push({ expected: "number", code: "invalid_type", input: W, inst: X, ...J ? { received: J } : {} }), $;
  };
});
var HQ = O("$ZodNumber", (X, Q) => {
  sW.init(X, Q), v42.init(X, Q);
});
var BQ = O("$ZodBoolean", (X, Q) => {
  X0.init(X, Q), X._zod.pattern = iW, X._zod.parse = ($, Y) => {
    if (Q.coerce) try {
      $.value = Boolean($.value);
    } catch (J) {
    }
    let W = $.value;
    if (typeof W === "boolean") return $;
    return $.issues.push({ expected: "boolean", code: "invalid_type", input: W, inst: X }), $;
  };
});
var zQ = O("$ZodNull", (X, Q) => {
  X0.init(X, Q), X._zod.pattern = nW, X._zod.values = /* @__PURE__ */ new Set([null]), X._zod.parse = ($, Y) => {
    let W = $.value;
    if (W === null) return $;
    return $.issues.push({ expected: "null", code: "invalid_type", input: W, inst: X }), $;
  };
});
var KQ = O("$ZodUnknown", (X, Q) => {
  X0.init(X, Q), X._zod.parse = ($) => $;
});
var UQ = O("$ZodNever", (X, Q) => {
  X0.init(X, Q), X._zod.parse = ($, Y) => {
    return $.issues.push({ expected: "never", code: "invalid_type", input: $.value, inst: X }), $;
  };
});
function UJ(X, Q, $) {
  if (X.issues.length) Q.issues.push(...B1($, X.issues));
  Q.value[$] = X.value;
}
var VQ = O("$ZodArray", (X, Q) => {
  X0.init(X, Q), X._zod.parse = ($, Y) => {
    let W = $.value;
    if (!Array.isArray(W)) return $.issues.push({ expected: "array", code: "invalid_type", input: W, inst: X }), $;
    $.value = Array(W.length);
    let J = [];
    for (let G = 0; G < W.length; G++) {
      let H = W[G], B = Q.element._zod.run({ value: H, issues: [] }, Y);
      if (B instanceof Promise) J.push(B.then((z) => UJ(z, $, G)));
      else UJ(B, $, G);
    }
    if (J.length) return Promise.all(J).then(() => $);
    return $;
  };
});
function k4(X, Q, $) {
  if (X.issues.length) Q.issues.push(...B1($, X.issues));
  Q.value[$] = X.value;
}
function VJ(X, Q, $, Y) {
  if (X.issues.length) if (Y[$] === void 0) if ($ in Y) Q.value[$] = void 0;
  else Q.value[$] = X.value;
  else Q.issues.push(...B1($, X.issues));
  else if (X.value === void 0) {
    if ($ in Y) Q.value[$] = void 0;
  } else Q.value[$] = X.value;
}
var T4 = O("$ZodObject", (X, Q) => {
  X0.init(X, Q);
  let $ = AX(() => {
    let V = Object.keys(Q.shape);
    for (let U of V) if (!(Q.shape[U] instanceof X0)) throw Error(`Invalid element at key "${U}": expected a Zod schema`);
    let L = I8(Q.shape);
    return { shape: Q.shape, keys: V, keySet: new Set(V), numKeys: V.length, optionalKeys: new Set(L) };
  });
  Y0(X._zod, "propValues", () => {
    let V = Q.shape, L = {};
    for (let U in V) {
      let F = V[U]._zod;
      if (F.values) {
        L[U] ?? (L[U] = /* @__PURE__ */ new Set());
        for (let q of F.values) L[U].add(q);
      }
    }
    return L;
  });
  let Y = (V) => {
    let L = new u8(["shape", "payload", "ctx"]), U = $.value, F = (M) => {
      let R = s1(M);
      return `shape[${R}]._zod.run({ value: input[${R}], issues: [] }, ctx)`;
    };
    L.write("const input = payload.value;");
    let q = /* @__PURE__ */ Object.create(null), N = 0;
    for (let M of U.keys) q[M] = `key_${N++}`;
    L.write("const newResult = {}");
    for (let M of U.keys) if (U.optionalKeys.has(M)) {
      let R = q[M];
      L.write(`const ${R} = ${F(M)};`);
      let S = s1(M);
      L.write(`
        if (${R}.issues.length) {
          if (input[${S}] === undefined) {
            if (${S} in input) {
              newResult[${S}] = undefined;
            }
          } else {
            payload.issues = payload.issues.concat(
              ${R}.issues.map((iss) => ({
                ...iss,
                path: iss.path ? [${S}, ...iss.path] : [${S}],
              }))
            );
          }
        } else if (${R}.value === undefined) {
          if (${S} in input) newResult[${S}] = undefined;
        } else {
          newResult[${S}] = ${R}.value;
        }
        `);
    } else {
      let R = q[M];
      L.write(`const ${R} = ${F(M)};`), L.write(`
          if (${R}.issues.length) payload.issues = payload.issues.concat(${R}.issues.map(iss => ({
            ...iss,
            path: iss.path ? [${s1(M)}, ...iss.path] : [${s1(M)}]
          })));`), L.write(`newResult[${s1(M)}] = ${R}.value`);
    }
    L.write("payload.value = newResult;"), L.write("return payload;");
    let A = L.compile();
    return (M, R) => A(V, M, R);
  }, W, J = Z6, G = !I4.jitless, B = G && R8.value, z = Q.catchall, K;
  X._zod.parse = (V, L) => {
    K ?? (K = $.value);
    let U = V.value;
    if (!J(U)) return V.issues.push({ expected: "object", code: "invalid_type", input: U, inst: X }), V;
    let F = [];
    if (G && B && L?.async === false && L.jitless !== true) {
      if (!W) W = Y(Q.shape);
      V = W(V, L);
    } else {
      V.value = {};
      let R = K.shape;
      for (let S of K.keys) {
        let C = R[S], K0 = C._zod.run({ value: U[S], issues: [] }, L), U0 = C._zod.optin === "optional" && C._zod.optout === "optional";
        if (K0 instanceof Promise) F.push(K0.then((s) => U0 ? VJ(s, V, S, U) : k4(s, V, S)));
        else if (U0) VJ(K0, V, S, U);
        else k4(K0, V, S);
      }
    }
    if (!z) return F.length ? Promise.all(F).then(() => V) : V;
    let q = [], N = K.keySet, A = z._zod, M = A.def.type;
    for (let R of Object.keys(U)) {
      if (N.has(R)) continue;
      if (M === "never") {
        q.push(R);
        continue;
      }
      let S = A.run({ value: U[R], issues: [] }, L);
      if (S instanceof Promise) F.push(S.then((C) => k4(C, V, R)));
      else k4(S, V, R);
    }
    if (q.length) V.issues.push({ code: "unrecognized_keys", keys: q, input: U, inst: X });
    if (!F.length) return V;
    return Promise.all(F).then(() => {
      return V;
    });
  };
});
function LJ(X, Q, $, Y) {
  for (let W of X) if (W.issues.length === 0) return Q.value = W.value, Q;
  return Q.issues.push({ code: "invalid_union", input: Q.value, inst: $, errors: X.map((W) => W.issues.map((J) => o0(J, Y, u0()))) }), Q;
}
var _4 = O("$ZodUnion", (X, Q) => {
  X0.init(X, Q), Y0(X._zod, "optin", () => Q.options.some(($) => $._zod.optin === "optional") ? "optional" : void 0), Y0(X._zod, "optout", () => Q.options.some(($) => $._zod.optout === "optional") ? "optional" : void 0), Y0(X._zod, "values", () => {
    if (Q.options.every(($) => $._zod.values)) return new Set(Q.options.flatMap(($) => Array.from($._zod.values)));
    return;
  }), Y0(X._zod, "pattern", () => {
    if (Q.options.every(($) => $._zod.pattern)) {
      let $ = Q.options.map((Y) => Y._zod.pattern);
      return new RegExp(`^(${$.map((Y) => MX(Y.source)).join("|")})$`);
    }
    return;
  }), X._zod.parse = ($, Y) => {
    let W = false, J = [];
    for (let G of Q.options) {
      let H = G._zod.run({ value: $.value, issues: [] }, Y);
      if (H instanceof Promise) J.push(H), W = true;
      else {
        if (H.issues.length === 0) return H;
        J.push(H);
      }
    }
    if (!W) return LJ(J, $, X, Y);
    return Promise.all(J).then((G) => {
      return LJ(G, $, X, Y);
    });
  };
});
var LQ = O("$ZodDiscriminatedUnion", (X, Q) => {
  _4.init(X, Q);
  let $ = X._zod.parse;
  Y0(X._zod, "propValues", () => {
    let W = {};
    for (let J of Q.options) {
      let G = J._zod.propValues;
      if (!G || Object.keys(G).length === 0) throw Error(`Invalid discriminated union option at index "${Q.options.indexOf(J)}"`);
      for (let [H, B] of Object.entries(G)) {
        if (!W[H]) W[H] = /* @__PURE__ */ new Set();
        for (let z of B) W[H].add(z);
      }
    }
    return W;
  });
  let Y = AX(() => {
    let W = Q.options, J = /* @__PURE__ */ new Map();
    for (let G of W) {
      let H = G._zod.propValues[Q.discriminator];
      if (!H || H.size === 0) throw Error(`Invalid discriminated union option at index "${Q.options.indexOf(G)}"`);
      for (let B of H) {
        if (J.has(B)) throw Error(`Duplicate discriminator value "${String(B)}"`);
        J.set(B, G);
      }
    }
    return J;
  });
  X._zod.parse = (W, J) => {
    let G = W.value;
    if (!Z6(G)) return W.issues.push({ code: "invalid_type", expected: "object", input: G, inst: X }), W;
    let H = Y.value.get(G?.[Q.discriminator]);
    if (H) return H._zod.run(W, J);
    if (Q.unionFallback) return $(W, J);
    return W.issues.push({ code: "invalid_union", errors: [], note: "No matching discriminator", input: G, path: [Q.discriminator], inst: X }), W;
  };
});
var qQ = O("$ZodIntersection", (X, Q) => {
  X0.init(X, Q), X._zod.parse = ($, Y) => {
    let W = $.value, J = Q.left._zod.run({ value: W, issues: [] }, Y), G = Q.right._zod.run({ value: W, issues: [] }, Y);
    if (J instanceof Promise || G instanceof Promise) return Promise.all([J, G]).then(([B, z]) => {
      return qJ($, B, z);
    });
    return qJ($, J, G);
  };
});
function l8(X, Q) {
  if (X === Q) return { valid: true, data: X };
  if (X instanceof Date && Q instanceof Date && +X === +Q) return { valid: true, data: X };
  if (C6(X) && C6(Q)) {
    let $ = Object.keys(Q), Y = Object.keys(X).filter((J) => $.indexOf(J) !== -1), W = { ...X, ...Q };
    for (let J of Y) {
      let G = l8(X[J], Q[J]);
      if (!G.valid) return { valid: false, mergeErrorPath: [J, ...G.mergeErrorPath] };
      W[J] = G.data;
    }
    return { valid: true, data: W };
  }
  if (Array.isArray(X) && Array.isArray(Q)) {
    if (X.length !== Q.length) return { valid: false, mergeErrorPath: [] };
    let $ = [];
    for (let Y = 0; Y < X.length; Y++) {
      let W = X[Y], J = Q[Y], G = l8(W, J);
      if (!G.valid) return { valid: false, mergeErrorPath: [Y, ...G.mergeErrorPath] };
      $.push(G.data);
    }
    return { valid: true, data: $ };
  }
  return { valid: false, mergeErrorPath: [] };
}
function qJ(X, Q, $) {
  if (Q.issues.length) X.issues.push(...Q.issues);
  if ($.issues.length) X.issues.push(...$.issues);
  if (e1(X)) return X;
  let Y = l8(Q.value, $.value);
  if (!Y.valid) throw Error(`Unmergable intersection. Error path: ${JSON.stringify(Y.mergeErrorPath)}`);
  return X.value = Y.data, X;
}
var FQ = O("$ZodRecord", (X, Q) => {
  X0.init(X, Q), X._zod.parse = ($, Y) => {
    let W = $.value;
    if (!C6(W)) return $.issues.push({ expected: "record", code: "invalid_type", input: W, inst: X }), $;
    let J = [];
    if (Q.keyType._zod.values) {
      let G = Q.keyType._zod.values;
      $.value = {};
      for (let B of G) if (typeof B === "string" || typeof B === "number" || typeof B === "symbol") {
        let z = Q.valueType._zod.run({ value: W[B], issues: [] }, Y);
        if (z instanceof Promise) J.push(z.then((K) => {
          if (K.issues.length) $.issues.push(...B1(B, K.issues));
          $.value[B] = K.value;
        }));
        else {
          if (z.issues.length) $.issues.push(...B1(B, z.issues));
          $.value[B] = z.value;
        }
      }
      let H;
      for (let B in W) if (!G.has(B)) H = H ?? [], H.push(B);
      if (H && H.length > 0) $.issues.push({ code: "unrecognized_keys", input: W, inst: X, keys: H });
    } else {
      $.value = {};
      for (let G of Reflect.ownKeys(W)) {
        if (G === "__proto__") continue;
        let H = Q.keyType._zod.run({ value: G, issues: [] }, Y);
        if (H instanceof Promise) throw Error("Async schemas not supported in object keys currently");
        if (H.issues.length) {
          $.issues.push({ origin: "record", code: "invalid_key", issues: H.issues.map((z) => o0(z, Y, u0())), input: G, path: [G], inst: X }), $.value[H.value] = H.value;
          continue;
        }
        let B = Q.valueType._zod.run({ value: W[G], issues: [] }, Y);
        if (B instanceof Promise) J.push(B.then((z) => {
          if (z.issues.length) $.issues.push(...B1(G, z.issues));
          $.value[H.value] = z.value;
        }));
        else {
          if (B.issues.length) $.issues.push(...B1(G, B.issues));
          $.value[H.value] = B.value;
        }
      }
    }
    if (J.length) return Promise.all(J).then(() => $);
    return $;
  };
});
var NQ = O("$ZodEnum", (X, Q) => {
  X0.init(X, Q);
  let $ = DX(Q.entries);
  X._zod.values = new Set($), X._zod.pattern = new RegExp(`^(${$.filter((Y) => E8.has(typeof Y)).map((Y) => typeof Y === "string" ? x1(Y) : Y.toString()).join("|")})$`), X._zod.parse = (Y, W) => {
    let J = Y.value;
    if (X._zod.values.has(J)) return Y;
    return Y.issues.push({ code: "invalid_value", values: $, input: J, inst: X }), Y;
  };
});
var OQ = O("$ZodLiteral", (X, Q) => {
  X0.init(X, Q), X._zod.values = new Set(Q.values), X._zod.pattern = new RegExp(`^(${Q.values.map(($) => typeof $ === "string" ? x1($) : $ ? $.toString() : String($)).join("|")})$`), X._zod.parse = ($, Y) => {
    let W = $.value;
    if (X._zod.values.has(W)) return $;
    return $.issues.push({ code: "invalid_value", values: Q.values, input: W, inst: X }), $;
  };
});
var DQ = O("$ZodTransform", (X, Q) => {
  X0.init(X, Q), X._zod.parse = ($, Y) => {
    let W = Q.transform($.value, $);
    if (Y.async) return (W instanceof Promise ? W : Promise.resolve(W)).then((G) => {
      return $.value = G, $;
    });
    if (W instanceof Promise) throw new _1();
    return $.value = W, $;
  };
});
var AQ = O("$ZodOptional", (X, Q) => {
  X0.init(X, Q), X._zod.optin = "optional", X._zod.optout = "optional", Y0(X._zod, "values", () => {
    return Q.innerType._zod.values ? /* @__PURE__ */ new Set([...Q.innerType._zod.values, void 0]) : void 0;
  }), Y0(X._zod, "pattern", () => {
    let $ = Q.innerType._zod.pattern;
    return $ ? new RegExp(`^(${MX($.source)})?$`) : void 0;
  }), X._zod.parse = ($, Y) => {
    if (Q.innerType._zod.optin === "optional") return Q.innerType._zod.run($, Y);
    if ($.value === void 0) return $;
    return Q.innerType._zod.run($, Y);
  };
});
var wQ = O("$ZodNullable", (X, Q) => {
  X0.init(X, Q), Y0(X._zod, "optin", () => Q.innerType._zod.optin), Y0(X._zod, "optout", () => Q.innerType._zod.optout), Y0(X._zod, "pattern", () => {
    let $ = Q.innerType._zod.pattern;
    return $ ? new RegExp(`^(${MX($.source)}|null)$`) : void 0;
  }), Y0(X._zod, "values", () => {
    return Q.innerType._zod.values ? /* @__PURE__ */ new Set([...Q.innerType._zod.values, null]) : void 0;
  }), X._zod.parse = ($, Y) => {
    if ($.value === null) return $;
    return Q.innerType._zod.run($, Y);
  };
});
var MQ = O("$ZodDefault", (X, Q) => {
  X0.init(X, Q), X._zod.optin = "optional", Y0(X._zod, "values", () => Q.innerType._zod.values), X._zod.parse = ($, Y) => {
    if ($.value === void 0) return $.value = Q.defaultValue, $;
    let W = Q.innerType._zod.run($, Y);
    if (W instanceof Promise) return W.then((J) => FJ(J, Q));
    return FJ(W, Q);
  };
});
function FJ(X, Q) {
  if (X.value === void 0) X.value = Q.defaultValue;
  return X;
}
var jQ = O("$ZodPrefault", (X, Q) => {
  X0.init(X, Q), X._zod.optin = "optional", Y0(X._zod, "values", () => Q.innerType._zod.values), X._zod.parse = ($, Y) => {
    if ($.value === void 0) $.value = Q.defaultValue;
    return Q.innerType._zod.run($, Y);
  };
});
var RQ = O("$ZodNonOptional", (X, Q) => {
  X0.init(X, Q), Y0(X._zod, "values", () => {
    let $ = Q.innerType._zod.values;
    return $ ? new Set([...$].filter((Y) => Y !== void 0)) : void 0;
  }), X._zod.parse = ($, Y) => {
    let W = Q.innerType._zod.run($, Y);
    if (W instanceof Promise) return W.then((J) => NJ(J, X));
    return NJ(W, X);
  };
});
function NJ(X, Q) {
  if (!X.issues.length && X.value === void 0) X.issues.push({ code: "invalid_type", expected: "nonoptional", input: X.value, inst: Q });
  return X;
}
var EQ = O("$ZodCatch", (X, Q) => {
  X0.init(X, Q), X._zod.optin = "optional", Y0(X._zod, "optout", () => Q.innerType._zod.optout), Y0(X._zod, "values", () => Q.innerType._zod.values), X._zod.parse = ($, Y) => {
    let W = Q.innerType._zod.run($, Y);
    if (W instanceof Promise) return W.then((J) => {
      if ($.value = J.value, J.issues.length) $.value = Q.catchValue({ ...$, error: { issues: J.issues.map((G) => o0(G, Y, u0())) }, input: $.value }), $.issues = [];
      return $;
    });
    if ($.value = W.value, W.issues.length) $.value = Q.catchValue({ ...$, error: { issues: W.issues.map((J) => o0(J, Y, u0())) }, input: $.value }), $.issues = [];
    return $;
  };
});
var IQ = O("$ZodPipe", (X, Q) => {
  X0.init(X, Q), Y0(X._zod, "values", () => Q.in._zod.values), Y0(X._zod, "optin", () => Q.in._zod.optin), Y0(X._zod, "optout", () => Q.out._zod.optout), X._zod.parse = ($, Y) => {
    let W = Q.in._zod.run($, Y);
    if (W instanceof Promise) return W.then((J) => OJ(J, Q, Y));
    return OJ(W, Q, Y);
  };
});
function OJ(X, Q, $) {
  if (e1(X)) return X;
  return Q.out._zod.run({ value: X.value, issues: X.issues }, $);
}
var bQ = O("$ZodReadonly", (X, Q) => {
  X0.init(X, Q), Y0(X._zod, "propValues", () => Q.innerType._zod.propValues), Y0(X._zod, "values", () => Q.innerType._zod.values), Y0(X._zod, "optin", () => Q.innerType._zod.optin), Y0(X._zod, "optout", () => Q.innerType._zod.optout), X._zod.parse = ($, Y) => {
    let W = Q.innerType._zod.run($, Y);
    if (W instanceof Promise) return W.then(DJ);
    return DJ(W);
  };
});
function DJ(X) {
  return X.value = Object.freeze(X.value), X;
}
var PQ = O("$ZodCustom", (X, Q) => {
  w0.init(X, Q), X0.init(X, Q), X._zod.parse = ($, Y) => {
    return $;
  }, X._zod.check = ($) => {
    let Y = $.value, W = Q.fn(Y);
    if (W instanceof Promise) return W.then((J) => AJ(J, $, Y, X));
    AJ(W, $, Y, X);
    return;
  };
});
function AJ(X, Q, $, Y) {
  if (!X) {
    let W = { code: "custom", input: $, inst: Y, path: [...Y._zod.def.path ?? []], continue: !Y._zod.def.abort };
    if (Y._zod.def.params) W.params = Y._zod.def.params;
    Q.issues.push(P8(W));
  }
}
var cV = (X) => {
  let Q = typeof X;
  switch (Q) {
    case "number":
      return Number.isNaN(X) ? "NaN" : "number";
    case "object": {
      if (Array.isArray(X)) return "array";
      if (X === null) return "null";
      if (Object.getPrototypeOf(X) !== Object.prototype && X.constructor) return X.constructor.name;
    }
  }
  return Q;
};
var pV = () => {
  let X = { string: { unit: "characters", verb: "to have" }, file: { unit: "bytes", verb: "to have" }, array: { unit: "items", verb: "to have" }, set: { unit: "items", verb: "to have" } };
  function Q(Y) {
    return X[Y] ?? null;
  }
  let $ = { regex: "input", email: "email address", url: "URL", emoji: "emoji", uuid: "UUID", uuidv4: "UUIDv4", uuidv6: "UUIDv6", nanoid: "nanoid", guid: "GUID", cuid: "cuid", cuid2: "cuid2", ulid: "ULID", xid: "XID", ksuid: "KSUID", datetime: "ISO datetime", date: "ISO date", time: "ISO time", duration: "ISO duration", ipv4: "IPv4 address", ipv6: "IPv6 address", cidrv4: "IPv4 range", cidrv6: "IPv6 range", base64: "base64-encoded string", base64url: "base64url-encoded string", json_string: "JSON string", e164: "E.164 number", jwt: "JWT", template_literal: "input" };
  return (Y) => {
    switch (Y.code) {
      case "invalid_type":
        return `Invalid input: expected ${Y.expected}, received ${cV(Y.input)}`;
      case "invalid_value":
        if (Y.values.length === 1) return `Invalid input: expected ${S4(Y.values[0])}`;
        return `Invalid option: expected one of ${b4(Y.values, "|")}`;
      case "too_big": {
        let W = Y.inclusive ? "<=" : "<", J = Q(Y.origin);
        if (J) return `Too big: expected ${Y.origin ?? "value"} to have ${W}${Y.maximum.toString()} ${J.unit ?? "elements"}`;
        return `Too big: expected ${Y.origin ?? "value"} to be ${W}${Y.maximum.toString()}`;
      }
      case "too_small": {
        let W = Y.inclusive ? ">=" : ">", J = Q(Y.origin);
        if (J) return `Too small: expected ${Y.origin} to have ${W}${Y.minimum.toString()} ${J.unit}`;
        return `Too small: expected ${Y.origin} to be ${W}${Y.minimum.toString()}`;
      }
      case "invalid_format": {
        let W = Y;
        if (W.format === "starts_with") return `Invalid string: must start with "${W.prefix}"`;
        if (W.format === "ends_with") return `Invalid string: must end with "${W.suffix}"`;
        if (W.format === "includes") return `Invalid string: must include "${W.includes}"`;
        if (W.format === "regex") return `Invalid string: must match pattern ${W.pattern}`;
        return `Invalid ${$[W.format] ?? Y.format}`;
      }
      case "not_multiple_of":
        return `Invalid number: must be a multiple of ${Y.divisor}`;
      case "unrecognized_keys":
        return `Unrecognized key${Y.keys.length > 1 ? "s" : ""}: ${b4(Y.keys, ", ")}`;
      case "invalid_key":
        return `Invalid key in ${Y.origin}`;
      case "invalid_union":
        return "Invalid input";
      case "invalid_element":
        return `Invalid value in ${Y.origin}`;
      default:
        return "Invalid input";
    }
  };
};
function SQ() {
  return { localeError: pV() };
}
var dV = Symbol("ZodOutput");
var iV = Symbol("ZodInput");
var x4 = class {
  constructor() {
    this._map = /* @__PURE__ */ new WeakMap(), this._idmap = /* @__PURE__ */ new Map();
  }
  add(X, ...Q) {
    let $ = Q[0];
    if (this._map.set(X, $), $ && typeof $ === "object" && "id" in $) {
      if (this._idmap.has($.id)) throw Error(`ID ${$.id} already exists in the registry`);
      this._idmap.set($.id, X);
    }
    return this;
  }
  remove(X) {
    return this._map.delete(X), this;
  }
  get(X) {
    let Q = X._zod.parent;
    if (Q) {
      let $ = { ...this.get(Q) ?? {} };
      return delete $.id, { ...$, ...this._map.get(X) };
    }
    return this._map.get(X);
  }
  has(X) {
    return this._map.has(X);
  }
};
function IJ() {
  return new x4();
}
var y1 = IJ();
function ZQ(X, Q) {
  return new X({ type: "string", ...y(Q) });
}
function CQ(X, Q) {
  return new X({ type: "string", format: "email", check: "string_format", abort: false, ...y(Q) });
}
function y4(X, Q) {
  return new X({ type: "string", format: "guid", check: "string_format", abort: false, ...y(Q) });
}
function kQ(X, Q) {
  return new X({ type: "string", format: "uuid", check: "string_format", abort: false, ...y(Q) });
}
function vQ(X, Q) {
  return new X({ type: "string", format: "uuid", check: "string_format", abort: false, version: "v4", ...y(Q) });
}
function TQ(X, Q) {
  return new X({ type: "string", format: "uuid", check: "string_format", abort: false, version: "v6", ...y(Q) });
}
function _Q(X, Q) {
  return new X({ type: "string", format: "uuid", check: "string_format", abort: false, version: "v7", ...y(Q) });
}
function xQ(X, Q) {
  return new X({ type: "string", format: "url", check: "string_format", abort: false, ...y(Q) });
}
function yQ(X, Q) {
  return new X({ type: "string", format: "emoji", check: "string_format", abort: false, ...y(Q) });
}
function gQ(X, Q) {
  return new X({ type: "string", format: "nanoid", check: "string_format", abort: false, ...y(Q) });
}
function hQ(X, Q) {
  return new X({ type: "string", format: "cuid", check: "string_format", abort: false, ...y(Q) });
}
function fQ(X, Q) {
  return new X({ type: "string", format: "cuid2", check: "string_format", abort: false, ...y(Q) });
}
function uQ(X, Q) {
  return new X({ type: "string", format: "ulid", check: "string_format", abort: false, ...y(Q) });
}
function lQ(X, Q) {
  return new X({ type: "string", format: "xid", check: "string_format", abort: false, ...y(Q) });
}
function mQ(X, Q) {
  return new X({ type: "string", format: "ksuid", check: "string_format", abort: false, ...y(Q) });
}
function cQ(X, Q) {
  return new X({ type: "string", format: "ipv4", check: "string_format", abort: false, ...y(Q) });
}
function pQ(X, Q) {
  return new X({ type: "string", format: "ipv6", check: "string_format", abort: false, ...y(Q) });
}
function dQ(X, Q) {
  return new X({ type: "string", format: "cidrv4", check: "string_format", abort: false, ...y(Q) });
}
function iQ(X, Q) {
  return new X({ type: "string", format: "cidrv6", check: "string_format", abort: false, ...y(Q) });
}
function nQ(X, Q) {
  return new X({ type: "string", format: "base64", check: "string_format", abort: false, ...y(Q) });
}
function rQ(X, Q) {
  return new X({ type: "string", format: "base64url", check: "string_format", abort: false, ...y(Q) });
}
function oQ(X, Q) {
  return new X({ type: "string", format: "e164", check: "string_format", abort: false, ...y(Q) });
}
function tQ(X, Q) {
  return new X({ type: "string", format: "jwt", check: "string_format", abort: false, ...y(Q) });
}
function bJ(X, Q) {
  return new X({ type: "string", format: "datetime", check: "string_format", offset: false, local: false, precision: null, ...y(Q) });
}
function PJ(X, Q) {
  return new X({ type: "string", format: "date", check: "string_format", ...y(Q) });
}
function SJ(X, Q) {
  return new X({ type: "string", format: "time", check: "string_format", precision: null, ...y(Q) });
}
function ZJ(X, Q) {
  return new X({ type: "string", format: "duration", check: "string_format", ...y(Q) });
}
function aQ(X, Q) {
  return new X({ type: "number", checks: [], ...y(Q) });
}
function sQ(X, Q) {
  return new X({ type: "number", check: "number_format", abort: false, format: "safeint", ...y(Q) });
}
function eQ(X, Q) {
  return new X({ type: "boolean", ...y(Q) });
}
function X$(X, Q) {
  return new X({ type: "null", ...y(Q) });
}
function Q$(X) {
  return new X({ type: "unknown" });
}
function $$(X, Q) {
  return new X({ type: "never", ...y(Q) });
}
function g4(X, Q) {
  return new h8({ check: "less_than", ...y(Q), value: X, inclusive: false });
}
function bX(X, Q) {
  return new h8({ check: "less_than", ...y(Q), value: X, inclusive: true });
}
function h4(X, Q) {
  return new f8({ check: "greater_than", ...y(Q), value: X, inclusive: false });
}
function PX(X, Q) {
  return new f8({ check: "greater_than", ...y(Q), value: X, inclusive: true });
}
function f4(X, Q) {
  return new aW({ check: "multiple_of", ...y(Q), value: X });
}
function u4(X, Q) {
  return new eW({ check: "max_length", ...y(Q), maximum: X });
}
function k6(X, Q) {
  return new XJ({ check: "min_length", ...y(Q), minimum: X });
}
function l4(X, Q) {
  return new QJ({ check: "length_equals", ...y(Q), length: X });
}
function Y$(X, Q) {
  return new $J({ check: "string_format", format: "regex", ...y(Q), pattern: X });
}
function W$(X) {
  return new YJ({ check: "string_format", format: "lowercase", ...y(X) });
}
function J$(X) {
  return new WJ({ check: "string_format", format: "uppercase", ...y(X) });
}
function G$(X, Q) {
  return new JJ({ check: "string_format", format: "includes", ...y(Q), includes: X });
}
function H$(X, Q) {
  return new GJ({ check: "string_format", format: "starts_with", ...y(Q), prefix: X });
}
function B$(X, Q) {
  return new HJ({ check: "string_format", format: "ends_with", ...y(Q), suffix: X });
}
function $6(X) {
  return new BJ({ check: "overwrite", tx: X });
}
function z$(X) {
  return $6((Q) => Q.normalize(X));
}
function K$() {
  return $6((X) => X.trim());
}
function U$() {
  return $6((X) => X.toLowerCase());
}
function V$() {
  return $6((X) => X.toUpperCase());
}
function CJ(X, Q, $) {
  return new X({ type: "array", element: Q, ...y($) });
}
function L$(X, Q, $) {
  let Y = y($);
  return Y.abort ?? (Y.abort = true), new X({ type: "custom", check: "custom", fn: Q, ...Y });
}
function q$(X, Q, $) {
  return new X({ type: "custom", check: "custom", fn: Q, ...y($) });
}
var PL = O("ZodMiniType", (X, Q) => {
  if (!X._zod) throw Error("Uninitialized schema in ZodMiniType.");
  X0.init(X, Q), X.def = Q, X.parse = ($, Y) => k8(X, $, Y, { callee: X.parse }), X.safeParse = ($, Y) => X6(X, $, Y), X.parseAsync = async ($, Y) => T8(X, $, Y, { callee: X.parseAsync }), X.safeParseAsync = async ($, Y) => Q6(X, $, Y), X.check = (...$) => {
    return X.clone({ ...Q, checks: [...Q.checks ?? [], ...$.map((Y) => typeof Y === "function" ? { _zod: { check: Y, def: { check: "custom" }, onattach: [] } } : Y)] });
  }, X.clone = ($, Y) => l0(X, $, Y), X.brand = () => X, X.register = ($, Y) => {
    return $.add(X, Y), X;
  };
});
var SL = O("ZodMiniObject", (X, Q) => {
  T4.init(X, Q), PL.init(X, Q), i.defineLazy(X, "shape", () => Q.shape);
});
var SX = {};
U7(SX, { time: () => w$, duration: () => M$, datetime: () => D$, date: () => A$, ZodISOTime: () => yJ, ZodISODuration: () => gJ, ZodISODateTime: () => _J, ZodISODate: () => xJ });
var _J = O("ZodISODateTime", (X, Q) => {
  wJ.init(X, Q), H0.init(X, Q);
});
function D$(X) {
  return bJ(_J, X);
}
var xJ = O("ZodISODate", (X, Q) => {
  MJ.init(X, Q), H0.init(X, Q);
});
function A$(X) {
  return PJ(xJ, X);
}
var yJ = O("ZodISOTime", (X, Q) => {
  jJ.init(X, Q), H0.init(X, Q);
});
function w$(X) {
  return SJ(yJ, X);
}
var gJ = O("ZodISODuration", (X, Q) => {
  RJ.init(X, Q), H0.init(X, Q);
});
function M$(X) {
  return ZJ(gJ, X);
}
var hJ = (X, Q) => {
  Z4.init(X, Q), X.name = "ZodError", Object.defineProperties(X, { format: { value: ($) => Z8(X, $) }, flatten: { value: ($) => S8(X, $) }, addIssue: { value: ($) => X.issues.push($) }, addIssues: { value: ($) => X.issues.push(...$) }, isEmpty: { get() {
    return X.issues.length === 0;
  } } });
};
var nS = O("ZodError", hJ);
var ZX = O("ZodError", hJ, { Parent: Error });
var fJ = C8(ZX);
var uJ = v8(ZX);
var lJ = _8(ZX);
var mJ = x8(ZX);
var z0 = O("ZodType", (X, Q) => {
  return X0.init(X, Q), X.def = Q, Object.defineProperty(X, "_def", { value: Q }), X.check = (...$) => {
    return X.clone({ ...Q, checks: [...Q.checks ?? [], ...$.map((Y) => typeof Y === "function" ? { _zod: { check: Y, def: { check: "custom" }, onattach: [] } } : Y)] });
  }, X.clone = ($, Y) => l0(X, $, Y), X.brand = () => X, X.register = ($, Y) => {
    return $.add(X, Y), X;
  }, X.parse = ($, Y) => fJ(X, $, Y, { callee: X.parse }), X.safeParse = ($, Y) => lJ(X, $, Y), X.parseAsync = async ($, Y) => uJ(X, $, Y, { callee: X.parseAsync }), X.safeParseAsync = async ($, Y) => mJ(X, $, Y), X.spa = X.safeParseAsync, X.refine = ($, Y) => X.check(Iq($, Y)), X.superRefine = ($) => X.check(bq($)), X.overwrite = ($) => X.check($6($)), X.optional = () => v(X), X.nullable = () => dJ(X), X.nullish = () => v(dJ(X)), X.nonoptional = ($) => Dq(X, $), X.array = () => r(X), X.or = ($) => J0([X, $]), X.and = ($) => i4(X, $), X.transform = ($) => R$(X, tJ($)), X.default = ($) => Fq(X, $), X.prefault = ($) => Oq(X, $), X.catch = ($) => wq(X, $), X.pipe = ($) => R$(X, $), X.readonly = () => Rq(X), X.describe = ($) => {
    let Y = X.clone();
    return y1.add(Y, { description: $ }), Y;
  }, Object.defineProperty(X, "description", { get() {
    return y1.get(X)?.description;
  }, configurable: true }), X.meta = (...$) => {
    if ($.length === 0) return y1.get(X);
    let Y = X.clone();
    return y1.add(Y, $[0]), Y;
  }, X.isOptional = () => X.safeParse(void 0).success, X.isNullable = () => X.safeParse(null).success, X;
});
var iJ = O("_ZodString", (X, Q) => {
  IX.init(X, Q), z0.init(X, Q);
  let $ = X._zod.bag;
  X.format = $.format ?? null, X.minLength = $.minimum ?? null, X.maxLength = $.maximum ?? null, X.regex = (...Y) => X.check(Y$(...Y)), X.includes = (...Y) => X.check(G$(...Y)), X.startsWith = (...Y) => X.check(H$(...Y)), X.endsWith = (...Y) => X.check(B$(...Y)), X.min = (...Y) => X.check(k6(...Y)), X.max = (...Y) => X.check(u4(...Y)), X.length = (...Y) => X.check(l4(...Y)), X.nonempty = (...Y) => X.check(k6(1, ...Y)), X.lowercase = (Y) => X.check(W$(Y)), X.uppercase = (Y) => X.check(J$(Y)), X.trim = () => X.check(K$()), X.normalize = (...Y) => X.check(z$(...Y)), X.toLowerCase = () => X.check(U$()), X.toUpperCase = () => X.check(V$());
});
var gL = O("ZodString", (X, Q) => {
  IX.init(X, Q), iJ.init(X, Q), X.email = ($) => X.check(CQ(hL, $)), X.url = ($) => X.check(xQ(fL, $)), X.jwt = ($) => X.check(tQ(Xq, $)), X.emoji = ($) => X.check(yQ(uL, $)), X.guid = ($) => X.check(y4(cJ, $)), X.uuid = ($) => X.check(kQ(d4, $)), X.uuidv4 = ($) => X.check(vQ(d4, $)), X.uuidv6 = ($) => X.check(TQ(d4, $)), X.uuidv7 = ($) => X.check(_Q(d4, $)), X.nanoid = ($) => X.check(gQ(lL, $)), X.guid = ($) => X.check(y4(cJ, $)), X.cuid = ($) => X.check(hQ(mL, $)), X.cuid2 = ($) => X.check(fQ(cL, $)), X.ulid = ($) => X.check(uQ(pL, $)), X.base64 = ($) => X.check(nQ(aL, $)), X.base64url = ($) => X.check(rQ(sL, $)), X.xid = ($) => X.check(lQ(dL, $)), X.ksuid = ($) => X.check(mQ(iL, $)), X.ipv4 = ($) => X.check(cQ(nL, $)), X.ipv6 = ($) => X.check(pQ(rL, $)), X.cidrv4 = ($) => X.check(dQ(oL, $)), X.cidrv6 = ($) => X.check(iQ(tL, $)), X.e164 = ($) => X.check(oQ(eL, $)), X.datetime = ($) => X.check(D$($)), X.date = ($) => X.check(A$($)), X.time = ($) => X.check(w$($)), X.duration = ($) => X.check(M$($));
});
function D(X) {
  return ZQ(gL, X);
}
var H0 = O("ZodStringFormat", (X, Q) => {
  W0.init(X, Q), iJ.init(X, Q);
});
var hL = O("ZodEmail", (X, Q) => {
  p8.init(X, Q), H0.init(X, Q);
});
var cJ = O("ZodGUID", (X, Q) => {
  m8.init(X, Q), H0.init(X, Q);
});
var d4 = O("ZodUUID", (X, Q) => {
  c8.init(X, Q), H0.init(X, Q);
});
var fL = O("ZodURL", (X, Q) => {
  d8.init(X, Q), H0.init(X, Q);
});
var uL = O("ZodEmoji", (X, Q) => {
  i8.init(X, Q), H0.init(X, Q);
});
var lL = O("ZodNanoID", (X, Q) => {
  n8.init(X, Q), H0.init(X, Q);
});
var mL = O("ZodCUID", (X, Q) => {
  r8.init(X, Q), H0.init(X, Q);
});
var cL = O("ZodCUID2", (X, Q) => {
  o8.init(X, Q), H0.init(X, Q);
});
var pL = O("ZodULID", (X, Q) => {
  t8.init(X, Q), H0.init(X, Q);
});
var dL = O("ZodXID", (X, Q) => {
  a8.init(X, Q), H0.init(X, Q);
});
var iL = O("ZodKSUID", (X, Q) => {
  s8.init(X, Q), H0.init(X, Q);
});
var nL = O("ZodIPv4", (X, Q) => {
  e8.init(X, Q), H0.init(X, Q);
});
var rL = O("ZodIPv6", (X, Q) => {
  XQ.init(X, Q), H0.init(X, Q);
});
var oL = O("ZodCIDRv4", (X, Q) => {
  QQ.init(X, Q), H0.init(X, Q);
});
var tL = O("ZodCIDRv6", (X, Q) => {
  $Q.init(X, Q), H0.init(X, Q);
});
var aL = O("ZodBase64", (X, Q) => {
  YQ.init(X, Q), H0.init(X, Q);
});
var sL = O("ZodBase64URL", (X, Q) => {
  WQ.init(X, Q), H0.init(X, Q);
});
var eL = O("ZodE164", (X, Q) => {
  JQ.init(X, Q), H0.init(X, Q);
});
var Xq = O("ZodJWT", (X, Q) => {
  GQ.init(X, Q), H0.init(X, Q);
});
var nJ = O("ZodNumber", (X, Q) => {
  v42.init(X, Q), z0.init(X, Q), X.gt = (Y, W) => X.check(h4(Y, W)), X.gte = (Y, W) => X.check(PX(Y, W)), X.min = (Y, W) => X.check(PX(Y, W)), X.lt = (Y, W) => X.check(g4(Y, W)), X.lte = (Y, W) => X.check(bX(Y, W)), X.max = (Y, W) => X.check(bX(Y, W)), X.int = (Y) => X.check(pJ(Y)), X.safe = (Y) => X.check(pJ(Y)), X.positive = (Y) => X.check(h4(0, Y)), X.nonnegative = (Y) => X.check(PX(0, Y)), X.negative = (Y) => X.check(g4(0, Y)), X.nonpositive = (Y) => X.check(bX(0, Y)), X.multipleOf = (Y, W) => X.check(f4(Y, W)), X.step = (Y, W) => X.check(f4(Y, W)), X.finite = () => X;
  let $ = X._zod.bag;
  X.minValue = Math.max($.minimum ?? Number.NEGATIVE_INFINITY, $.exclusiveMinimum ?? Number.NEGATIVE_INFINITY) ?? null, X.maxValue = Math.min($.maximum ?? Number.POSITIVE_INFINITY, $.exclusiveMaximum ?? Number.POSITIVE_INFINITY) ?? null, X.isInt = ($.format ?? "").includes("int") || Number.isSafeInteger($.multipleOf ?? 0.5), X.isFinite = true, X.format = $.format ?? null;
});
function Q0(X) {
  return aQ(nJ, X);
}
var Qq = O("ZodNumberFormat", (X, Q) => {
  HQ.init(X, Q), nJ.init(X, Q);
});
function pJ(X) {
  return sQ(Qq, X);
}
var $q = O("ZodBoolean", (X, Q) => {
  BQ.init(X, Q), z0.init(X, Q);
});
function M0(X) {
  return eQ($q, X);
}
var Yq = O("ZodNull", (X, Q) => {
  zQ.init(X, Q), z0.init(X, Q);
});
function E$(X) {
  return X$(Yq, X);
}
var Wq = O("ZodUnknown", (X, Q) => {
  KQ.init(X, Q), z0.init(X, Q);
});
function N0() {
  return Q$(Wq);
}
var Jq = O("ZodNever", (X, Q) => {
  UQ.init(X, Q), z0.init(X, Q);
});
function Gq(X) {
  return $$(Jq, X);
}
var Hq = O("ZodArray", (X, Q) => {
  VQ.init(X, Q), z0.init(X, Q), X.element = Q.element, X.min = ($, Y) => X.check(k6($, Y)), X.nonempty = ($) => X.check(k6(1, $)), X.max = ($, Y) => X.check(u4($, Y)), X.length = ($, Y) => X.check(l4($, Y)), X.unwrap = () => X.element;
});
function r(X, Q) {
  return CJ(Hq, X, Q);
}
var rJ = O("ZodObject", (X, Q) => {
  T4.init(X, Q), z0.init(X, Q), i.defineLazy(X, "shape", () => Q.shape), X.keyof = () => j0(Object.keys(X._zod.def.shape)), X.catchall = ($) => X.clone({ ...X._zod.def, catchall: $ }), X.passthrough = () => X.clone({ ...X._zod.def, catchall: N0() }), X.loose = () => X.clone({ ...X._zod.def, catchall: N0() }), X.strict = () => X.clone({ ...X._zod.def, catchall: Gq() }), X.strip = () => X.clone({ ...X._zod.def, catchall: void 0 }), X.extend = ($) => {
    return i.extend(X, $);
  }, X.merge = ($) => i.merge(X, $), X.pick = ($) => i.pick(X, $), X.omit = ($) => i.omit(X, $), X.partial = (...$) => i.partial(aJ, X, $[0]), X.required = (...$) => i.required(sJ, X, $[0]);
});
function I(X, Q) {
  let $ = { type: "object", get shape() {
    return i.assignProp(this, "shape", { ...X }), this.shape;
  }, ...i.normalizeParams(Q) };
  return new rJ($);
}
function c0(X, Q) {
  return new rJ({ type: "object", get shape() {
    return i.assignProp(this, "shape", { ...X }), this.shape;
  }, catchall: N0(), ...i.normalizeParams(Q) });
}
var oJ = O("ZodUnion", (X, Q) => {
  _4.init(X, Q), z0.init(X, Q), X.options = Q.options;
});
function J0(X, Q) {
  return new oJ({ type: "union", options: X, ...i.normalizeParams(Q) });
}
var Bq = O("ZodDiscriminatedUnion", (X, Q) => {
  oJ.init(X, Q), LQ.init(X, Q);
});
function I$(X, Q, $) {
  return new Bq({ type: "union", options: Q, discriminator: X, ...i.normalizeParams($) });
}
var zq = O("ZodIntersection", (X, Q) => {
  qQ.init(X, Q), z0.init(X, Q);
});
function i4(X, Q) {
  return new zq({ type: "intersection", left: X, right: Q });
}
var Kq = O("ZodRecord", (X, Q) => {
  FQ.init(X, Q), z0.init(X, Q), X.keyType = Q.keyType, X.valueType = Q.valueType;
});
function O0(X, Q, $) {
  return new Kq({ type: "record", keyType: X, valueType: Q, ...i.normalizeParams($) });
}
var j$ = O("ZodEnum", (X, Q) => {
  NQ.init(X, Q), z0.init(X, Q), X.enum = Q.entries, X.options = Object.values(Q.entries);
  let $ = new Set(Object.keys(Q.entries));
  X.extract = (Y, W) => {
    let J = {};
    for (let G of Y) if ($.has(G)) J[G] = Q.entries[G];
    else throw Error(`Key ${G} not found in enum`);
    return new j$({ ...Q, checks: [], ...i.normalizeParams(W), entries: J });
  }, X.exclude = (Y, W) => {
    let J = { ...Q.entries };
    for (let G of Y) if ($.has(G)) delete J[G];
    else throw Error(`Key ${G} not found in enum`);
    return new j$({ ...Q, checks: [], ...i.normalizeParams(W), entries: J });
  };
});
function j0(X, Q) {
  let $ = Array.isArray(X) ? Object.fromEntries(X.map((Y) => [Y, Y])) : X;
  return new j$({ type: "enum", entries: $, ...i.normalizeParams(Q) });
}
var Uq = O("ZodLiteral", (X, Q) => {
  OQ.init(X, Q), z0.init(X, Q), X.values = new Set(Q.values), Object.defineProperty(X, "value", { get() {
    if (Q.values.length > 1) throw Error("This schema contains multiple valid literal values. Use `.values` instead.");
    return Q.values[0];
  } });
});
function T(X, Q) {
  return new Uq({ type: "literal", values: Array.isArray(X) ? X : [X], ...i.normalizeParams(Q) });
}
var Vq = O("ZodTransform", (X, Q) => {
  DQ.init(X, Q), z0.init(X, Q), X._zod.parse = ($, Y) => {
    $.addIssue = (J) => {
      if (typeof J === "string") $.issues.push(i.issue(J, $.value, Q));
      else {
        let G = J;
        if (G.fatal) G.continue = false;
        G.code ?? (G.code = "custom"), G.input ?? (G.input = $.value), G.inst ?? (G.inst = X), G.continue ?? (G.continue = true), $.issues.push(i.issue(G));
      }
    };
    let W = Q.transform($.value, $);
    if (W instanceof Promise) return W.then((J) => {
      return $.value = J, $;
    });
    return $.value = W, $;
  };
});
function tJ(X) {
  return new Vq({ type: "transform", transform: X });
}
var aJ = O("ZodOptional", (X, Q) => {
  AQ.init(X, Q), z0.init(X, Q), X.unwrap = () => X._zod.def.innerType;
});
function v(X) {
  return new aJ({ type: "optional", innerType: X });
}
var Lq = O("ZodNullable", (X, Q) => {
  wQ.init(X, Q), z0.init(X, Q), X.unwrap = () => X._zod.def.innerType;
});
function dJ(X) {
  return new Lq({ type: "nullable", innerType: X });
}
var qq = O("ZodDefault", (X, Q) => {
  MQ.init(X, Q), z0.init(X, Q), X.unwrap = () => X._zod.def.innerType, X.removeDefault = X.unwrap;
});
function Fq(X, Q) {
  return new qq({ type: "default", innerType: X, get defaultValue() {
    return typeof Q === "function" ? Q() : Q;
  } });
}
var Nq = O("ZodPrefault", (X, Q) => {
  jQ.init(X, Q), z0.init(X, Q), X.unwrap = () => X._zod.def.innerType;
});
function Oq(X, Q) {
  return new Nq({ type: "prefault", innerType: X, get defaultValue() {
    return typeof Q === "function" ? Q() : Q;
  } });
}
var sJ = O("ZodNonOptional", (X, Q) => {
  RQ.init(X, Q), z0.init(X, Q), X.unwrap = () => X._zod.def.innerType;
});
function Dq(X, Q) {
  return new sJ({ type: "nonoptional", innerType: X, ...i.normalizeParams(Q) });
}
var Aq = O("ZodCatch", (X, Q) => {
  EQ.init(X, Q), z0.init(X, Q), X.unwrap = () => X._zod.def.innerType, X.removeCatch = X.unwrap;
});
function wq(X, Q) {
  return new Aq({ type: "catch", innerType: X, catchValue: typeof Q === "function" ? Q : () => Q });
}
var Mq = O("ZodPipe", (X, Q) => {
  IQ.init(X, Q), z0.init(X, Q), X.in = Q.in, X.out = Q.out;
});
function R$(X, Q) {
  return new Mq({ type: "pipe", in: X, out: Q });
}
var jq = O("ZodReadonly", (X, Q) => {
  bQ.init(X, Q), z0.init(X, Q);
});
function Rq(X) {
  return new jq({ type: "readonly", innerType: X });
}
var eJ = O("ZodCustom", (X, Q) => {
  PQ.init(X, Q), z0.init(X, Q);
});
function Eq(X, Q) {
  let $ = new w0({ check: "custom", ...i.normalizeParams(Q) });
  return $._zod.check = X, $;
}
function X5(X, Q) {
  return L$(eJ, X ?? (() => true), Q);
}
function Iq(X, Q = {}) {
  return q$(eJ, X, Q);
}
function bq(X, Q) {
  let $ = Eq((Y) => {
    return Y.addIssue = (W) => {
      if (typeof W === "string") Y.issues.push(i.issue(W, Y.value, $._zod.def));
      else {
        let J = W;
        if (J.fatal) J.continue = false;
        J.code ?? (J.code = "custom"), J.input ?? (J.input = Y.value), J.inst ?? (J.inst = $), J.continue ?? (J.continue = !$._zod.def.abort), Y.issues.push(i.issue(J));
      }
    }, X(Y.value, Y);
  }, Q);
  return $;
}
function b$(X, Q) {
  return R$(tJ(X), Q);
}
u0(SQ());
var K1 = "io.modelcontextprotocol/related-task";
var r4 = "2.0";
var z1 = X5((X) => X !== null && (typeof X === "object" || typeof X === "function"));
var $5 = J0([D(), Q0().int()]);
var Y5 = D();
var Pq = c0({ ttl: J0([Q0(), E$()]).optional(), pollInterval: Q0().optional() });
var S$ = c0({ taskId: D() });
var Sq = c0({ progressToken: $5.optional(), [K1]: S$.optional() });
var _0 = c0({ task: Pq.optional(), _meta: Sq.optional() });
var R0 = I({ method: D(), params: _0.optional() });
var W6 = c0({ _meta: I({ [K1]: v(S$) }).passthrough().optional() });
var p0 = I({ method: D(), params: W6.optional() });
var b0 = c0({ _meta: c0({ [K1]: S$.optional() }).optional() });
var o4 = J0([D(), Q0().int()]);
var W5 = I({ jsonrpc: T(r4), id: o4, ...R0.shape }).strict();
var J5 = I({ jsonrpc: T(r4), ...p0.shape }).strict();
var H5 = I({ jsonrpc: T(r4), id: o4, result: b0 }).strict();
var x;
(function(X) {
  X[X.ConnectionClosed = -32e3] = "ConnectionClosed", X[X.RequestTimeout = -32001] = "RequestTimeout", X[X.ParseError = -32700] = "ParseError", X[X.InvalidRequest = -32600] = "InvalidRequest", X[X.MethodNotFound = -32601] = "MethodNotFound", X[X.InvalidParams = -32602] = "InvalidParams", X[X.InternalError = -32603] = "InternalError", X[X.UrlElicitationRequired = -32042] = "UrlElicitationRequired";
})(x || (x = {}));
var B5 = I({ jsonrpc: T(r4), id: o4, error: I({ code: Q0().int(), message: D(), data: v(N0()) }) }).strict();
var HZ = J0([W5, J5, H5, B5]);
var t4 = b0.strict();
var Zq = W6.extend({ requestId: o4, reason: D().optional() });
var a4 = p0.extend({ method: T("notifications/cancelled"), params: Zq });
var Cq = I({ src: D(), mimeType: D().optional(), sizes: r(D()).optional() });
var kX = I({ icons: r(Cq).optional() });
var _6 = I({ name: D(), title: D().optional() });
var K5 = _6.extend({ ..._6.shape, ...kX.shape, version: D(), websiteUrl: D().optional() });
var kq = i4(I({ applyDefaults: M0().optional() }), O0(D(), N0()));
var vq = b$((X) => {
  if (X && typeof X === "object" && !Array.isArray(X)) {
    if (Object.keys(X).length === 0) return { form: {} };
  }
  return X;
}, i4(I({ form: kq.optional(), url: z1.optional() }), O0(D(), N0()).optional()));
var Tq = I({ list: v(I({}).passthrough()), cancel: v(I({}).passthrough()), requests: v(I({ sampling: v(I({ createMessage: v(I({}).passthrough()) }).passthrough()), elicitation: v(I({ create: v(I({}).passthrough()) }).passthrough()) }).passthrough()) }).passthrough();
var _q = I({ list: v(I({}).passthrough()), cancel: v(I({}).passthrough()), requests: v(I({ tools: v(I({ call: v(I({}).passthrough()) }).passthrough()) }).passthrough()) }).passthrough();
var xq = I({ experimental: O0(D(), z1).optional(), sampling: I({ context: z1.optional(), tools: z1.optional() }).optional(), elicitation: vq.optional(), roots: I({ listChanged: M0().optional() }).optional(), tasks: v(Tq) });
var yq = _0.extend({ protocolVersion: D(), capabilities: xq, clientInfo: K5 });
var C$ = R0.extend({ method: T("initialize"), params: yq });
var gq = I({ experimental: O0(D(), z1).optional(), logging: z1.optional(), completions: z1.optional(), prompts: v(I({ listChanged: v(M0()) })), resources: I({ subscribe: M0().optional(), listChanged: M0().optional() }).optional(), tools: I({ listChanged: M0().optional() }).optional(), tasks: v(_q) }).passthrough();
var hq = b0.extend({ protocolVersion: D(), capabilities: gq, serverInfo: K5, instructions: D().optional() });
var k$ = p0.extend({ method: T("notifications/initialized") });
var s4 = R0.extend({ method: T("ping") });
var fq = I({ progress: Q0(), total: v(Q0()), message: v(D()) });
var uq = I({ ...W6.shape, ...fq.shape, progressToken: $5 });
var e4 = p0.extend({ method: T("notifications/progress"), params: uq });
var lq = _0.extend({ cursor: Y5.optional() });
var vX = R0.extend({ params: lq.optional() });
var TX = b0.extend({ nextCursor: v(Y5) });
var _X = I({ taskId: D(), status: j0(["working", "input_required", "completed", "failed", "cancelled"]), ttl: J0([Q0(), E$()]), createdAt: D(), lastUpdatedAt: D(), pollInterval: v(Q0()), statusMessage: v(D()) });
var x6 = b0.extend({ task: _X });
var mq = W6.merge(_X);
var xX = p0.extend({ method: T("notifications/tasks/status"), params: mq });
var X9 = R0.extend({ method: T("tasks/get"), params: _0.extend({ taskId: D() }) });
var Q9 = b0.merge(_X);
var $9 = R0.extend({ method: T("tasks/result"), params: _0.extend({ taskId: D() }) });
var Y9 = vX.extend({ method: T("tasks/list") });
var W9 = TX.extend({ tasks: r(_X) });
var U5 = R0.extend({ method: T("tasks/cancel"), params: _0.extend({ taskId: D() }) });
var V5 = b0.merge(_X);
var L5 = I({ uri: D(), mimeType: v(D()), _meta: O0(D(), N0()).optional() });
var q5 = L5.extend({ text: D() });
var v$ = D().refine((X) => {
  try {
    return atob(X), true;
  } catch (Q) {
    return false;
  }
}, { message: "Invalid Base64 string" });
var F5 = L5.extend({ blob: v$ });
var y6 = I({ audience: r(j0(["user", "assistant"])).optional(), priority: Q0().min(0).max(1).optional(), lastModified: SX.datetime({ offset: true }).optional() });
var N5 = I({ ..._6.shape, ...kX.shape, uri: D(), description: v(D()), mimeType: v(D()), annotations: y6.optional(), _meta: v(c0({})) });
var cq = I({ ..._6.shape, ...kX.shape, uriTemplate: D(), description: v(D()), mimeType: v(D()), annotations: y6.optional(), _meta: v(c0({})) });
var J9 = vX.extend({ method: T("resources/list") });
var pq = TX.extend({ resources: r(N5) });
var G9 = vX.extend({ method: T("resources/templates/list") });
var dq = TX.extend({ resourceTemplates: r(cq) });
var T$ = _0.extend({ uri: D() });
var iq = T$;
var H9 = R0.extend({ method: T("resources/read"), params: iq });
var nq = b0.extend({ contents: r(J0([q5, F5])) });
var rq = p0.extend({ method: T("notifications/resources/list_changed") });
var oq = T$;
var tq = R0.extend({ method: T("resources/subscribe"), params: oq });
var aq = T$;
var sq = R0.extend({ method: T("resources/unsubscribe"), params: aq });
var eq = W6.extend({ uri: D() });
var XF = p0.extend({ method: T("notifications/resources/updated"), params: eq });
var QF = I({ name: D(), description: v(D()), required: v(M0()) });
var $F = I({ ..._6.shape, ...kX.shape, description: v(D()), arguments: v(r(QF)), _meta: v(c0({})) });
var B9 = vX.extend({ method: T("prompts/list") });
var YF = TX.extend({ prompts: r($F) });
var WF = _0.extend({ name: D(), arguments: O0(D(), D()).optional() });
var z9 = R0.extend({ method: T("prompts/get"), params: WF });
var _$ = I({ type: T("text"), text: D(), annotations: y6.optional(), _meta: O0(D(), N0()).optional() });
var x$ = I({ type: T("image"), data: v$, mimeType: D(), annotations: y6.optional(), _meta: O0(D(), N0()).optional() });
var y$ = I({ type: T("audio"), data: v$, mimeType: D(), annotations: y6.optional(), _meta: O0(D(), N0()).optional() });
var JF = I({ type: T("tool_use"), name: D(), id: D(), input: I({}).passthrough(), _meta: v(I({}).passthrough()) }).passthrough();
var GF = I({ type: T("resource"), resource: J0([q5, F5]), annotations: y6.optional(), _meta: O0(D(), N0()).optional() });
var HF = N5.extend({ type: T("resource_link") });
var g$ = J0([_$, x$, y$, HF, GF]);
var BF = I({ role: j0(["user", "assistant"]), content: g$ });
var zF = b0.extend({ description: v(D()), messages: r(BF) });
var KF = p0.extend({ method: T("notifications/prompts/list_changed") });
var UF = I({ title: D().optional(), readOnlyHint: M0().optional(), destructiveHint: M0().optional(), idempotentHint: M0().optional(), openWorldHint: M0().optional() });
var VF = I({ taskSupport: j0(["required", "optional", "forbidden"]).optional() });
var O5 = I({ ..._6.shape, ...kX.shape, description: D().optional(), inputSchema: I({ type: T("object"), properties: O0(D(), z1).optional(), required: r(D()).optional() }).catchall(N0()), outputSchema: I({ type: T("object"), properties: O0(D(), z1).optional(), required: r(D()).optional() }).catchall(N0()).optional(), annotations: v(UF), execution: v(VF), _meta: O0(D(), N0()).optional() });
var K9 = vX.extend({ method: T("tools/list") });
var LF = TX.extend({ tools: r(O5) });
var U9 = b0.extend({ content: r(g$).default([]), structuredContent: O0(D(), N0()).optional(), isError: v(M0()) });
var BZ = U9.or(b0.extend({ toolResult: N0() }));
var qF = _0.extend({ name: D(), arguments: v(O0(D(), N0())) });
var g6 = R0.extend({ method: T("tools/call"), params: qF });
var FF = p0.extend({ method: T("notifications/tools/list_changed") });
var yX = j0(["debug", "info", "notice", "warning", "error", "critical", "alert", "emergency"]);
var NF = _0.extend({ level: yX });
var h$ = R0.extend({ method: T("logging/setLevel"), params: NF });
var OF = W6.extend({ level: yX, logger: D().optional(), data: N0() });
var DF = p0.extend({ method: T("notifications/message"), params: OF });
var AF = I({ name: D().optional() });
var wF = I({ hints: v(r(AF)), costPriority: v(Q0().min(0).max(1)), speedPriority: v(Q0().min(0).max(1)), intelligencePriority: v(Q0().min(0).max(1)) });
var MF = I({ mode: v(j0(["auto", "required", "none"])) });
var jF = I({ type: T("tool_result"), toolUseId: D().describe("The unique identifier for the corresponding tool call."), content: r(g$).default([]), structuredContent: I({}).passthrough().optional(), isError: v(M0()), _meta: v(I({}).passthrough()) }).passthrough();
var RF = I$("type", [_$, x$, y$]);
var n4 = I$("type", [_$, x$, y$, JF, jF]);
var EF = I({ role: j0(["user", "assistant"]), content: J0([n4, r(n4)]), _meta: v(I({}).passthrough()) }).passthrough();
var IF = _0.extend({ messages: r(EF), modelPreferences: wF.optional(), systemPrompt: D().optional(), includeContext: j0(["none", "thisServer", "allServers"]).optional(), temperature: Q0().optional(), maxTokens: Q0().int(), stopSequences: r(D()).optional(), metadata: z1.optional(), tools: v(r(O5)), toolChoice: v(MF) });
var bF = R0.extend({ method: T("sampling/createMessage"), params: IF });
var f$ = b0.extend({ model: D(), stopReason: v(j0(["endTurn", "stopSequence", "maxTokens"]).or(D())), role: j0(["user", "assistant"]), content: RF });
var u$ = b0.extend({ model: D(), stopReason: v(j0(["endTurn", "stopSequence", "maxTokens", "toolUse"]).or(D())), role: j0(["user", "assistant"]), content: J0([n4, r(n4)]) });
var PF = I({ type: T("boolean"), title: D().optional(), description: D().optional(), default: M0().optional() });
var SF = I({ type: T("string"), title: D().optional(), description: D().optional(), minLength: Q0().optional(), maxLength: Q0().optional(), format: j0(["email", "uri", "date", "date-time"]).optional(), default: D().optional() });
var ZF = I({ type: j0(["number", "integer"]), title: D().optional(), description: D().optional(), minimum: Q0().optional(), maximum: Q0().optional(), default: Q0().optional() });
var CF = I({ type: T("string"), title: D().optional(), description: D().optional(), enum: r(D()), default: D().optional() });
var kF = I({ type: T("string"), title: D().optional(), description: D().optional(), oneOf: r(I({ const: D(), title: D() })), default: D().optional() });
var vF = I({ type: T("string"), title: D().optional(), description: D().optional(), enum: r(D()), enumNames: r(D()).optional(), default: D().optional() });
var TF = J0([CF, kF]);
var _F = I({ type: T("array"), title: D().optional(), description: D().optional(), minItems: Q0().optional(), maxItems: Q0().optional(), items: I({ type: T("string"), enum: r(D()) }), default: r(D()).optional() });
var xF = I({ type: T("array"), title: D().optional(), description: D().optional(), minItems: Q0().optional(), maxItems: Q0().optional(), items: I({ anyOf: r(I({ const: D(), title: D() })) }), default: r(D()).optional() });
var yF = J0([_F, xF]);
var gF = J0([vF, TF, yF]);
var hF = J0([gF, PF, SF, ZF]);
var fF = _0.extend({ mode: T("form").optional(), message: D(), requestedSchema: I({ type: T("object"), properties: O0(D(), hF), required: r(D()).optional() }) });
var uF = _0.extend({ mode: T("url"), message: D(), elicitationId: D(), url: D().url() });
var lF = J0([fF, uF]);
var mF = R0.extend({ method: T("elicitation/create"), params: lF });
var cF = W6.extend({ elicitationId: D() });
var pF = p0.extend({ method: T("notifications/elicitation/complete"), params: cF });
var V9 = b0.extend({ action: j0(["accept", "decline", "cancel"]), content: b$((X) => X === null ? void 0 : X, O0(D(), J0([D(), Q0(), M0(), r(D())])).optional()) });
var dF = I({ type: T("ref/resource"), uri: D() });
var iF = I({ type: T("ref/prompt"), name: D() });
var nF = _0.extend({ ref: J0([iF, dF]), argument: I({ name: D(), value: D() }), context: I({ arguments: O0(D(), D()).optional() }).optional() });
var L9 = R0.extend({ method: T("completion/complete"), params: nF });
var rF = b0.extend({ completion: c0({ values: r(D()).max(100), total: v(Q0().int()), hasMore: v(M0()) }) });
var oF = I({ uri: D().startsWith("file://"), name: D().optional(), _meta: O0(D(), N0()).optional() });
var tF = R0.extend({ method: T("roots/list") });
var l$ = b0.extend({ roots: r(oF) });
var aF = p0.extend({ method: T("notifications/roots/list_changed") });
var zZ = J0([s4, C$, L9, h$, z9, B9, J9, G9, H9, tq, sq, g6, K9, X9, $9, Y9]);
var KZ = J0([a4, e4, k$, aF, xX]);
var UZ = J0([t4, f$, u$, V9, l$, Q9, W9, x6]);
var VZ = J0([s4, bF, mF, tF, X9, $9, Y9]);
var LZ = J0([a4, e4, DF, XF, rq, FF, KF, xX, pF]);
var qZ = J0([t4, hq, rF, zF, YF, pq, dq, nq, U9, LF, Q9, W9, x6]);
var j5 = Symbol("Let zodToJsonSchema decide on which parser to use");
var XN = new Set("ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvxyz0123456789");
var gz = K7(cY(), 1);
var hz = K7(yz(), 1);
var mz = Symbol.for("mcp.completable");
var lz;
(function(X) {
  X.Completable = "McpCompletable";
})(lz || (lz = {}));
function h_({ prompt: X, options: Q }) {
  let { systemPrompt: $, settingSources: Y, sandbox: W, ...J } = Q ?? {}, G, H;
  if ($ === void 0) G = "";
  else if (typeof $ === "string") G = $;
  else if ($.type === "preset") H = $.append;
  let B = J.pathToClaudeCodeExecutable;
  if (!B) {
    let q6 = EE(import.meta.url), F6 = rz(q6, "..");
    B = rz(F6, "cli.js");
  }
  process.env.CLAUDE_AGENT_SDK_VERSION = "0.2.15";
  let { abortController: z = N6(), additionalDirectories: K = [], agent: V, agents: L, allowedTools: U = [], betas: F, canUseTool: q, continue: N, cwd: A, disallowedTools: M = [], tools: R, env: S, executable: C = j6() ? "bun" : "node", executableArgs: K0 = [], extraArgs: U0 = {}, fallbackModel: s, enableFileCheckpointing: D0, forkSession: q0, hooks: W1, includePartialMessages: P1, persistSession: U6, maxThinkingTokens: d, maxTurns: Q8, maxBudgetUsd: o6, mcpServers: V6, model: t6, outputFormat: a6, permissionMode: B4 = "default", allowDangerouslySkipPermissions: S0 = false, permissionPromptToolName: S1, plugins: s6, resume: oz, resumeSessionAt: tz, stderr: az, strictMcpConfig: sz } = J, G7 = a6?.type === "json_schema" ? a6.schema : void 0, L6 = S;
  if (!L6) L6 = { ...process.env };
  if (!L6.CLAUDE_CODE_ENTRYPOINT) L6.CLAUDE_CODE_ENTRYPOINT = "sdk-ts";
  if (D0) L6.CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING = "true";
  if (!B) throw Error("pathToClaudeCodeExecutable is required");
  let $8 = {}, H7 = /* @__PURE__ */ new Map();
  if (V6) for (let [q6, F6] of Object.entries(V6)) if (F6.type === "sdk" && "instance" in F6) H7.set(q6, F6.instance), $8[q6] = { type: "sdk", name: q6 };
  else $8[q6] = F6;
  let ez = typeof X === "string", B7 = new XX({ abortController: z, additionalDirectories: K, agent: V, betas: F, cwd: A, executable: C, executableArgs: K0, extraArgs: U0, pathToClaudeCodeExecutable: B, env: L6, forkSession: q0, stderr: az, maxThinkingTokens: d, maxTurns: Q8, maxBudgetUsd: o6, model: t6, fallbackModel: s, jsonSchema: G7, permissionMode: B4, allowDangerouslySkipPermissions: S0, permissionPromptToolName: S1, continueConversation: N, resume: oz, resumeSessionAt: tz, settingSources: Y ?? [], allowedTools: U, disallowedTools: M, tools: R, mcpServers: $8, strictMcpConfig: sz, canUseTool: !!q, hooks: !!W1, includePartialMessages: P1, persistSession: U6, plugins: s6, sandbox: W, spawnClaudeCodeProcess: J.spawnClaudeCodeProcess }), z7 = new $X(B7, ez, q, W1, z, H7, G7, { systemPrompt: G, appendSystemPrompt: H, agents: L });
  if (typeof X === "string") B7.write(Z0({ type: "user", session_id: "", message: { role: "user", content: [{ type: "text", text: X }] }, parent_tool_use_id: null }) + `
`);
  else z7.streamInput(X);
  return z7;
}

// dist/logger.js
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
var Logger = class {
  fileStream;
  logFilePath;
  minLevel = "info";
  constructor() {
    this.setupFileLogging();
  }
  setupFileLogging() {
    try {
      const tmpDir = os.tmpdir();
      const logDir = path.join(tmpDir, "claude-agent-insights");
      console.error(`[LOGGER] Setting up file logging, tmpDir=${tmpDir}, logDir=${logDir}`);
      if (!fs.existsSync(logDir)) {
        console.error(`[LOGGER] Creating log directory: ${logDir}`);
        fs.mkdirSync(logDir, { recursive: true });
      }
      const timestamp = (/* @__PURE__ */ new Date()).toISOString().replace(/[:.]/g, "-");
      this.logFilePath = path.join(logDir, `backend-${timestamp}.log`);
      console.error(`[LOGGER] Creating log file: ${this.logFilePath}`);
      this.fileStream = fs.createWriteStream(this.logFilePath, { flags: "a" });
      this.logToStderr("info", `Logging to file: ${this.logFilePath}`);
      console.error(`[LOGGER] File logging setup complete`);
    } catch (err) {
      console.error(`[LOGGER] FAILED to setup file logging: ${err}`);
      console.error(`[LOGGER] Stack: ${err.stack}`);
      this.logToStderr("warn", `Failed to setup file logging: ${err}`);
    }
  }
  shouldLog(level) {
    const levels = ["debug", "info", "warn", "error"];
    const minIndex = levels.indexOf(this.minLevel);
    const levelIndex = levels.indexOf(level);
    return levelIndex >= minIndex;
  }
  formatEntry(entry) {
    const parts = [
      `[${entry.timestamp}]`,
      `[${entry.level.toUpperCase()}]`,
      entry.message
    ];
    if (entry.context && Object.keys(entry.context).length > 0) {
      parts.push(JSON.stringify(entry.context));
    }
    return parts.join(" ");
  }
  logToStderr(level, message, context) {
    if (!this.shouldLog(level))
      return;
    const entry = {
      timestamp: (/* @__PURE__ */ new Date()).toISOString(),
      level,
      message,
      context
    };
    const formatted = this.formatEntry(entry);
    console.error(formatted);
    if (this.fileStream) {
      this.fileStream.write(formatted + "\n");
    }
  }
  setMinLevel(level) {
    this.minLevel = level;
  }
  debug(message, context) {
    this.logToStderr("debug", message, context);
  }
  info(message, context) {
    this.logToStderr("info", message, context);
  }
  warn(message, context) {
    this.logToStderr("warn", message, context);
  }
  error(message, context) {
    this.logToStderr("error", message, context);
  }
  getLogFilePath() {
    return this.logFilePath;
  }
  dispose() {
    if (this.fileStream) {
      this.fileStream.end();
    }
  }
};
var logger = new Logger();

// dist/callback-bridge.js
var CALLBACK_TIMEOUT_MS = 3e5;
var CallbackBridge = class {
  pending = /* @__PURE__ */ new Map();
  sessionId;
  send;
  constructor(sessionId, send) {
    this.sessionId = sessionId;
    this.send = send;
  }
  async requestPermission(toolName, toolInput, context) {
    const id = v4_default();
    logger.info("Requesting permission", {
      sessionId: this.sessionId,
      callbackId: id,
      toolName,
      toolUseID: context.toolUseID,
      agentID: context.agentID
    });
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        logger.warn("Permission request timed out", {
          sessionId: this.sessionId,
          callbackId: id,
          toolName
        });
        resolve({
          behavior: "deny",
          message: "Permission request timed out"
        });
      }, CALLBACK_TIMEOUT_MS);
      this.pending.set(id, {
        resolve,
        reject,
        timeout,
        meta: { type: "permission", toolName, toolInput, suggestions: context.suggestions }
      });
      this.send({
        type: "callback.request",
        id,
        session_id: this.sessionId,
        payload: {
          callback_type: "can_use_tool",
          tool_name: toolName,
          tool_input: toolInput,
          suggestions: context.suggestions,
          blocked_path: context.blockedPath,
          decision_reason: context.decisionReason,
          tool_use_id: context.toolUseID,
          agent_id: context.agentID
        }
      });
    });
  }
  async requestHook(event, input, toolUseId) {
    const id = v4_default();
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        resolve({});
      }, CALLBACK_TIMEOUT_MS);
      this.pending.set(id, {
        resolve,
        reject,
        timeout,
        meta: { type: "hook", event }
      });
      this.send({
        type: "callback.request",
        id,
        session_id: this.sessionId,
        payload: {
          callback_type: "hook",
          hook_event: event,
          hook_input: input,
          tool_use_id: toolUseId
        }
      });
    });
  }
  resolve(id, response) {
    const pending = this.pending.get(id);
    if (!pending) {
      logger.error("Unknown callback ID", {
        sessionId: this.sessionId,
        callbackId: id
      });
      return;
    }
    clearTimeout(pending.timeout);
    this.pending.delete(id);
    if ("behavior" in response) {
      const permResponse = response;
      logger.info("Permission callback resolved", {
        sessionId: this.sessionId,
        callbackId: id,
        behavior: permResponse.behavior
      });
      if (permResponse.behavior === "allow") {
        const meta = pending.meta?.type === "permission" ? pending.meta : void 0;
        const updatedInput = permResponse.updated_input;
        if (updatedInput === void 0) {
          logger.warn("Permission allow response missing updated_input", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta?.toolName
          });
        } else if (typeof updatedInput !== "object" || updatedInput === null) {
          logger.warn("Permission allow response has non-object updated_input", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta?.toolName,
            updatedInputType: typeof updatedInput
          });
        } else if (meta && Object.keys(updatedInput).length === 0 && Object.keys(meta.toolInput).length > 0) {
          logger.warn("Permission allow response has empty updated_input", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta.toolName
          });
        }
        if (meta?.suggestions && permResponse.updated_permissions === void 0) {
          logger.warn("Permission allow response missing updated_permissions", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta.toolName
          });
        }
        const result = { behavior: "allow" };
        if (permResponse.updated_input !== void 0) {
          result.updatedInput = permResponse.updated_input;
        }
        if (permResponse.updated_permissions !== void 0) {
          result.updatedPermissions = permResponse.updated_permissions;
        }
        logger.info("Resolving permission callback with result", {
          sessionId: this.sessionId,
          callbackId: id,
          result: JSON.stringify(result)
        });
        pending.resolve(result);
      } else {
        if (!permResponse.message) {
          logger.warn("Permission deny response missing message", {
            sessionId: this.sessionId,
            callbackId: id
          });
        }
        const denyResult = {
          behavior: "deny",
          message: permResponse.message ?? "Denied",
          interrupt: permResponse.interrupt
        };
        logger.info("Resolving permission callback with denial", {
          sessionId: this.sessionId,
          callbackId: id,
          result: JSON.stringify(denyResult)
        });
        pending.resolve(denyResult);
      }
    } else {
      const hookResponse = response;
      logger.info("Hook callback resolved", {
        sessionId: this.sessionId,
        callbackId: id
      });
      pending.resolve({
        continue: hookResponse.continue,
        suppressOutput: hookResponse.suppressOutput ?? hookResponse.suppress_output,
        stopReason: hookResponse.stopReason ?? hookResponse.stop_reason,
        decision: hookResponse.decision,
        systemMessage: hookResponse.system_message ?? hookResponse.systemMessage,
        reason: hookResponse.reason,
        hookSpecificOutput: hookResponse.hook_specific_output ?? hookResponse.hookSpecificOutput
      });
    }
  }
  cancelAll() {
    for (const [, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Session terminated"));
    }
    this.pending.clear();
  }
};

// dist/message-queue.js
var MessageQueue = class {
  messages = [];
  waiters = [];
  closed = false;
  /**
   * Push a message into the queue.
   * If there's a waiting consumer, it will be notified immediately.
   */
  push(message) {
    if (this.closed) {
      throw new Error("Cannot push to a closed queue");
    }
    if (this.waiters.length > 0) {
      const resolve = this.waiters.shift();
      resolve(message);
    } else {
      this.messages.push(message);
    }
  }
  /**
   * Close the queue. No more messages can be pushed.
   * All waiting consumers will receive null.
   */
  close() {
    this.closed = true;
    while (this.waiters.length > 0) {
      const resolve = this.waiters.shift();
      resolve(null);
    }
  }
  /**
   * Async generator that yields messages as they arrive.
   */
  async *generate() {
    while (!this.closed) {
      let message;
      if (this.messages.length > 0) {
        message = this.messages.shift();
      } else {
        message = await new Promise((resolve) => {
          this.waiters.push(resolve);
        });
      }
      if (message === null) {
        break;
      }
      yield message;
    }
  }
};

// dist/session-manager.js
var SessionManager = class {
  sessions = /* @__PURE__ */ new Map();
  send;
  constructor(send) {
    this.send = send;
  }
  async handleMessage(msg) {
    logger.debug("Handling message", { type: msg.type });
    switch (msg.type) {
      case "session.create":
        await this.createSession(msg);
        break;
      case "session.send":
        await this.sendMessage(msg);
        break;
      case "session.interrupt":
        await this.interruptSession(msg);
        break;
      case "session.kill":
        await this.killSession(msg);
        break;
      case "callback.response":
        await this.handleCallbackResponse(msg);
        break;
      case "query.call":
        await this.handleQueryCall(msg);
        break;
      default:
        logger.warn("Unknown message type", {
          type: msg.type
        });
        this.send({
          type: "error",
          id: msg.id,
          payload: {
            code: "INVALID_MESSAGE",
            message: `Unknown message type: ${msg.type}`
          }
        });
    }
  }
  async createSession(msg) {
    const sessionId = v4_default();
    const abortController = new AbortController();
    const callbacks = new CallbackBridge(sessionId, this.send);
    const messageQueue = new MessageQueue();
    logger.info("Creating session", {
      sessionId,
      cwd: msg.payload.cwd,
      promptLength: msg.payload.prompt.length
    });
    try {
      const options = {
        cwd: msg.payload.cwd,
        abortController,
        // Use system claude binary if available to avoid Node v25 compatibility issues
        pathToClaudeCodeExecutable: process.env.CLAUDE_CODE_PATH,
        // Note: Enable these for streaming support:
        // includePartialMessages: true,  // Real-time text updates
        // maxThinkingTokens: 16000,      // Extended thinking
        ...this.buildOptions(msg.payload.options, callbacks)
      };
      logger.info("Starting SDK query with streaming input mode", {
        sessionId,
        cwd: options.cwd,
        model: options.model,
        permissionMode: options.permissionMode,
        maxTurns: options.maxTurns,
        includePartialMessages: options.includePartialMessages,
        hasCanUseTool: !!options.canUseTool,
        hasHooks: !!options.hooks
      });
      logger.info("Environment", {
        CLAUDE_CODE_PATH: process.env.CLAUDE_CODE_PATH,
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY ? "***set***" : void 0,
        HOME: process.env.HOME
      });
      if (msg.payload.prompt.trim() !== "" || msg.payload.content?.length) {
        const content = msg.payload.content?.length ? msg.payload.content : msg.payload.prompt;
        const initialMessage = {
          type: "user",
          message: {
            role: "user",
            content
          },
          parent_tool_use_id: null,
          session_id: sessionId
        };
        messageQueue.push(initialMessage);
      }
      const q = h_({
        prompt: messageQueue.generate(),
        options
      });
      const session = {
        id: sessionId,
        query: q,
        messageQueue,
        abortController,
        callbacks,
        cwd: msg.payload.cwd
      };
      this.sessions.set(sessionId, session);
      this.send({
        type: "session.created",
        id: msg.id,
        session_id: sessionId,
        payload: {}
      });
      logger.info("Session created successfully", {
        sessionId,
        totalSessions: this.sessions.size
      });
      this.processMessages(session);
    } catch (err) {
      logger.error("Failed to create session", {
        sessionId,
        error: String(err)
      });
      this.send({
        type: "error",
        id: msg.id,
        payload: {
          code: "SESSION_CREATE_FAILED",
          message: String(err)
        }
      });
    }
  }
  buildOptions(opts, callbacks) {
    const baseCanUseTool = async (toolName, toolInput, context) => {
      return callbacks.requestPermission(toolName, toolInput, {
        suggestions: context.suggestions,
        blockedPath: context.blockedPath,
        decisionReason: context.decisionReason,
        toolUseID: context.toolUseID,
        agentID: context.agentID
      });
    };
    if (!opts) {
      logger.debug("No session options provided, using defaults");
      return { canUseTool: baseCanUseTool };
    }
    logger.debug("Building session options", {
      hasModel: !!opts.model,
      hasPermissionMode: !!opts.permission_mode,
      hasSystemPrompt: !!opts.system_prompt,
      hasHooks: !!opts.hooks,
      hasMcpServers: !!opts.mcp_servers
    });
    const result = {};
    if (opts.model)
      result.model = opts.model;
    if (opts.permission_mode)
      result.permissionMode = opts.permission_mode;
    if (opts.allow_dangerously_skip_permissions !== void 0) {
      result.allowDangerouslySkipPermissions = opts.allow_dangerously_skip_permissions;
    }
    if (opts.permission_prompt_tool_name) {
      result.permissionPromptToolName = opts.permission_prompt_tool_name;
    }
    if (opts.tools)
      result.tools = opts.tools;
    if (opts.plugins)
      result.plugins = opts.plugins;
    if (opts.strict_mcp_config !== void 0) {
      result.strictMcpConfig = opts.strict_mcp_config;
    }
    if (opts.resume)
      result.resume = opts.resume;
    if (opts.resume_session_at)
      result.resumeSessionAt = opts.resume_session_at;
    if (opts.allowed_tools)
      result.allowedTools = opts.allowed_tools;
    if (opts.disallowed_tools)
      result.disallowedTools = opts.disallowed_tools;
    if (opts.max_turns)
      result.maxTurns = opts.max_turns;
    if (opts.max_budget_usd !== void 0)
      result.maxBudgetUsd = opts.max_budget_usd;
    if (opts.max_thinking_tokens)
      result.maxThinkingTokens = opts.max_thinking_tokens;
    if (opts.include_partial_messages)
      result.includePartialMessages = opts.include_partial_messages;
    if (opts.enable_file_checkpointing !== void 0) {
      result.enableFileCheckpointing = opts.enable_file_checkpointing;
    }
    if (opts.additional_directories)
      result.additionalDirectories = opts.additional_directories;
    if (opts.fallback_model)
      result.fallbackModel = opts.fallback_model;
    if (opts.mcp_servers)
      result.mcpServers = opts.mcp_servers;
    if (opts.agents)
      result.agents = opts.agents;
    if (opts.sandbox)
      result.sandbox = opts.sandbox;
    if (opts.setting_sources)
      result.settingSources = opts.setting_sources;
    if (opts.betas)
      result.betas = opts.betas;
    if (opts.output_format)
      result.outputFormat = opts.output_format;
    if (opts.system_prompt !== void 0) {
      result.systemPrompt = opts.system_prompt;
    }
    result.canUseTool = baseCanUseTool;
    if (opts.hooks) {
      const hooks = {};
      for (const [event, configs] of Object.entries(opts.hooks)) {
        const hookEvent = event;
        hooks[hookEvent] = configs.map((config) => ({
          matcher: config.matcher,
          hooks: [
            async (input, toolUseId) => {
              return callbacks.requestHook(event, input, toolUseId);
            }
          ]
        }));
      }
      result.hooks = hooks;
    }
    return result;
  }
  async processMessages(session) {
    logger.info("Processing SDK messages", { sessionId: session.id });
    let messageCount = 0;
    try {
      for await (const message of session.query) {
        messageCount++;
        if (typeof message === "object" && message !== null && "session_id" in message) {
          session.sdkSessionId = message.session_id;
          logger.debug("Captured SDK session ID", {
            sessionId: session.id,
            sdkSessionId: session.sdkSessionId
          });
        }
        logger.debug("SDK message received", {
          sessionId: session.id,
          messageType: typeof message === "object" && message !== null && "type" in message ? message.type : typeof message,
          messageCount
        });
        this.send({
          type: "sdk.message",
          session_id: session.id,
          payload: message
        });
      }
      logger.info("SDK message stream completed", {
        sessionId: session.id,
        totalMessages: messageCount
      });
    } catch (err) {
      const error = err;
      const isAbort = error.name === "AbortError" || error.message?.includes("aborted by user");
      if (!isAbort) {
        logger.error("SDK error during message processing", {
          sessionId: session.id,
          error: String(err),
          stack: error.stack
        });
        this.send({
          type: "error",
          session_id: session.id,
          payload: {
            code: "SDK_ERROR",
            message: String(err)
          }
        });
      } else {
        logger.info("Session aborted", { sessionId: session.id });
      }
    }
  }
  async sendMessage(msg) {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      logger.warn("Session not found for send", { sessionId: msg.session_id });
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`
        }
      });
      return;
    }
    const content = msg.payload.content ? msg.payload.content : msg.payload.message;
    logger.info("Pushing message to session queue", {
      sessionId: msg.session_id,
      messageLength: msg.payload.message?.length ?? 0,
      contentBlockCount: msg.payload.content?.length ?? 0,
      sdkSessionId: session.sdkSessionId
    });
    const userMessage = {
      type: "user",
      message: {
        role: "user",
        content
      },
      parent_tool_use_id: null,
      session_id: msg.session_id
    };
    try {
      session.messageQueue.push(userMessage);
      logger.info("Message pushed to queue successfully", {
        sessionId: msg.session_id
      });
    } catch (err) {
      logger.error("Failed to push message to queue", {
        sessionId: msg.session_id,
        error: String(err)
      });
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SEND_MESSAGE_FAILED",
          message: String(err)
        }
      });
    }
  }
  async interruptSession(msg) {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`
        }
      });
      return;
    }
    try {
      await session.query.interrupt();
      this.send({
        type: "session.interrupted",
        id: msg.id,
        session_id: msg.session_id,
        payload: {}
      });
    } catch (err) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "INTERRUPT_FAILED",
          message: String(err)
        }
      });
    }
  }
  async killSession(msg) {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      logger.warn("Session not found for kill", { sessionId: msg.session_id });
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`
        }
      });
      return;
    }
    logger.info("Killing session", { sessionId: msg.session_id });
    session.abortController.abort();
    session.callbacks.cancelAll();
    session.messageQueue.close();
    this.sessions.delete(msg.session_id);
    logger.info("Session killed", {
      sessionId: msg.session_id,
      remainingSessions: this.sessions.size
    });
    this.send({
      type: "session.killed",
      id: msg.id,
      session_id: msg.session_id,
      payload: {}
    });
  }
  async handleCallbackResponse(msg) {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`
        }
      });
      return;
    }
    session.callbacks.resolve(msg.id, msg.payload);
  }
  async handleQueryCall(msg) {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`
        }
      });
      return;
    }
    try {
      const method = msg.payload.method;
      const args = msg.payload.args || [];
      let result;
      switch (method) {
        case "supportedModels":
          result = await session.query.supportedModels();
          break;
        case "supportedCommands":
          result = await session.query.supportedCommands();
          break;
        case "mcpServerStatus":
          result = await session.query.mcpServerStatus();
          break;
        case "setModel":
          await session.query.setModel(args[0]);
          result = null;
          break;
        case "setPermissionMode":
          await session.query.setPermissionMode(args[0]);
          result = null;
          break;
        // Note: accountInfo, setMaxThinkingTokens, rewindFiles are not available
        // in this SDK version - they may be added in future versions
        default:
          throw new Error(`Unknown or unsupported query method: ${method}`);
      }
      this.send({
        type: "query.result",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          success: true,
          result
        }
      });
    } catch (err) {
      this.send({
        type: "query.result",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          success: false,
          error: String(err)
        }
      });
    }
  }
  dispose() {
    for (const session of this.sessions.values()) {
      session.abortController.abort();
      session.callbacks.cancelAll();
    }
    this.sessions.clear();
  }
};

// dist/index.js
console.error("========================");
console.error("[BACKEND] Process starting...");
console.error("[BACKEND] PID:", process.pid);
console.error("[BACKEND] Node version:", process.version);
console.error("[BACKEND] CWD:", process.cwd());
console.error("========================");
if (!process.env.CLAUDE_CODE_PATH) {
  try {
    const which = execSync("which claude", {
      encoding: "utf-8"
    }).trim();
    if (which) {
      process.env.CLAUDE_CODE_PATH = which;
    }
  } catch (err) {
    console.error("[WARNING] claude binary not found in PATH, SDK will use bundled CLI which may not work on Node v25+");
  }
}
console.error("[BACKEND] Logger initialized, starting session manager...");
logger.info("Backend process starting", {
  pid: process.pid,
  claudeCodePath: process.env.CLAUDE_CODE_PATH
});
var messageLogPath = "/tmp/messages.jsonl";
var messageLogStream = fs2.createWriteStream(messageLogPath, { flags: "a" });
function logMessage(direction, message) {
  const entry = {
    timestamp: (/* @__PURE__ */ new Date()).toISOString(),
    direction,
    message
  };
  messageLogStream.write(JSON.stringify(entry) + "\n");
}
logger.info("Logging messages to", { path: messageLogPath });
var sessions = new SessionManager((msg) => {
  logMessage("OUT", msg);
  console.log(JSON.stringify(msg));
});
var rl = readline.createInterface({
  input: process.stdin,
  terminal: false
});
rl.on("line", async (line) => {
  if (!line.trim())
    return;
  logger.debug("Received message from stdin", { length: line.length });
  try {
    const msg = JSON.parse(line);
    logMessage("IN", msg);
    logger.debug("Parsed message", { type: msg.type });
    await sessions.handleMessage(msg);
  } catch (err) {
    logger.error("Failed to parse message from stdin", {
      error: String(err),
      line: line.substring(0, 100)
    });
    const errorMsg = {
      type: "error",
      payload: {
        code: "INVALID_MESSAGE",
        message: String(err)
      }
    };
    logMessage("OUT", errorMsg);
    console.log(JSON.stringify(errorMsg));
  }
});
rl.on("close", () => {
  logger.info("Stdin closed, shutting down");
  sessions.dispose();
  messageLogStream.end();
  logger.dispose();
  process.exit(0);
});
process.on("SIGTERM", () => {
  logger.info("Received SIGTERM, shutting down");
  sessions.dispose();
  messageLogStream.end();
  logger.dispose();
  process.exit(0);
});
process.on("SIGINT", () => {
  logger.info("Received SIGINT, shutting down");
  sessions.dispose();
  messageLogStream.end();
  logger.dispose();
  process.exit(0);
});
logger.info("Backend process ready", {
  logFile: logger.getLogFilePath()
});
