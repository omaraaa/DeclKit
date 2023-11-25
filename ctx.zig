const std = @import("std");

pub const AnyFn = struct {
    const Self = @This();
    Type: type,
    Value: *const anyopaque,

    pub fn init(comptime f: anytype) Self {
        comptime return Self{
            .Type = @TypeOf(f),
            .Value = &f,
        };
    }

    pub fn asTuple(comptime self: @This()) type {
        return @Type(.{
            .Struct = .{
                .layout = .Auto,
                .decls = &.{},
                .fields = &.{std.builtin.Type.StructField{
                    .name = "0",
                    .type = self.Type,
                    .is_comptime = false,
                    .default_value = self.Value,
                    .alignment = 0,
                }},
                .is_tuple = true,
            },
        });
    }

    pub fn GetType(comptime self: @This()) type {
        return self.Type;
    }

    pub fn GetReturnType(comptime self: @This()) type {
        return @typeInfo(self.Type).Fn.return_type.?;
    }

    pub fn GetReturnTypeStripError(comptime self: @This()) type {
        switch (@typeInfo(@typeInfo(self.Type).Fn.return_type.?)) {
            .ErrorUnion => |e| {
                return e.payload;
            },
            else => return @typeInfo(self.Type).Fn.return_type.?,
        }
    }

    pub fn ptr(comptime self: @This()) GetType(self) {
        return (self.asTuple(){})[0];
    }

    pub fn Args(comptime self: @This()) []const type {
        comptime var args: []const type = &[_]type{};
        inline for (@typeInfo(self.Type).Fn.args) |p| {
            args = args ++ &[_]type{p.type.?};
        }
        return args;
    }
};

pub const Ctx = struct {
    parent: ?*const Ctx = null,
    T: type,

    pub fn Instance(comptime ctx: Ctx) type {
        return struct {
            const Self = @This();
            pub const C = ctx;

            parent: if (ctx.parent) |p| p.Instance() else void,
            ptr: *ctx.T,

            pub inline fn push(self: Self, p: anytype) ctx.push(std.meta.Child(@TypeOf(p))).Instance() {
                return ctx.push(std.meta.Child(@TypeOf(p))).Instance(){
                    .parent = self,
                    .ptr = p,
                };
            }

            pub inline fn initInstance(self: Self) void {
                if (@typeInfo(ctx.T) == .Struct) {
                    inline for (std.meta.fields(C.T)) |f| {
                        if (comptime f.default_value) |dv| {
                            const V = @as(*const f.type, @ptrCast(@alignCast(dv))).*;
                            @field(self.ptr, f.name) = V;
                        }
                    }
                    if (comptime @hasDecl(ctx.T, "init") or @hasDecl(ctx.T, "metaInit")) {
                        if (comptime @hasDecl(ctx.T, "init")) {
                            const info = @typeInfo(@TypeOf(ctx.T.init)).Fn;
                            if (comptime !info.is_generic) {
                                if (comptime AnyFn.init(ctx.T.init).GetReturnTypeStripError() == ctx.T) {
                                    self.ptr.* = self.call(ctx.T.init);
                                } else {
                                    self.call(ctx.T.init);
                                }
                            }
                        }

                        if (comptime @hasDecl(ctx.T, "metaInit")) {
                            ctx.T.metaInit(self) catch |err| ctx.handleError(void, err);
                        }
                    }
                    if (comptime @hasDecl(ctx.T, "InitFields")) {
                        inline for (ctx.T.InitFields) |af| {
                            const info = std.meta.fieldInfo(ctx.T, af);
                            self.push(&@field(self.ptr, info.name)).initInstance();
                        }
                    }
                }
            }

            pub inline fn initFields(self: Self) void {
                inline for (std.meta.fields(C.T)) |f| {
                    var ptr: *f.type = &@field(self.ptr, f.name);
                    self.push(ptr).initInstance();
                }
            }

            pub inline fn tickInstance(self: Self) void {
                if (@typeInfo(ctx.T) == .Struct) {
                    if (comptime @hasDecl(ctx.T, "TickFields")) {
                        inline for (ctx.T.TickFields) |af| {
                            const info = std.meta.fieldInfo(ctx.T, af);
                            self.push(&@field(self.ptr, info.name)).tickInstance();
                        }
                    }
                    if (comptime @hasDecl(ctx.T, "metaTick")) {
                        ctx.T.metaTick(self) catch |err| self.handleError(void, err);
                    } else if (comptime @hasDecl(ctx.T, "tick")) {
                        self.call(ctx.T.tick);
                    }
                }
            }

            pub inline fn tickFields(self: Self) void {
                inline for (std.meta.fields(C.T)) |f| {
                    self.push(&@field(self.ptr, f.name)).tickInstance();
                }
            }

            pub inline fn deinitInstance(self: Self) void {
                if (@typeInfo(ctx.T) == .Struct) {
                    if (comptime @hasDecl(ctx.T, "metaDeinit")) {
                        ctx.T.metaDeinit(self) catch |err| self.handleError(void, err);
                    }
                    if (comptime @hasDecl(ctx.T, "deinit")) {
                        _ = self.call(ctx.T.deinit);
                    }
                    if (comptime @hasDecl(ctx.T, "InitFields")) {
                        comptime var i: usize = ctx.T.InitFields.len;
                        inline while (i > 0) {
                            comptime i -= 1;
                            const af = ctx.T.InitFields[i];
                            const info = std.meta.fieldInfo(ctx.T, af);
                            self.push(&@field(self.ptr, info.name)).initInstance();
                        }
                    }
                }
            }

            pub inline fn deinitFields(self: Self) void {
                const fields = std.meta.fields(C.T);
                comptime var i: usize = fields.len;
                inline while (i > 0) {
                    comptime i -= 1;
                    const f = fields[i];
                    self.push(&@field(self.ptr, f.name)).deinitInstance();
                }
            }

            pub fn call(self: Self, comptime ff: anytype) AnyFn.init(ff).GetReturnTypeStripError() {
                const f = AnyFn.init(ff);
                const fn_info = @typeInfo(f.Type).Fn;
                return _call(self, fn_info.params, ff, .{});
            }

            pub fn _call(self: Self, comptime Args: []const std.builtin.Type.Fn.Param, comptime ff: anytype, args_tuple: anytype) AnyFn.init(ff).GetReturnTypeStripError() {
                if (comptime Args.len > 0) {
                    const TO = Args[0].type;
                    return _call(self, Args[1..], ff, args_tuple ++ .{arg: {
                        if (TO) |T| {
                            switch (comptime @typeInfo(T)) {
                                .Struct, .Enum, .Union, .Opaque => {
                                    if (comptime @hasDecl(T, "metaArg")) {
                                        break :arg T.metaArg(self);
                                    }
                                },
                                else => {},
                            }
                            if (comptime T == ctx.T) {
                                break :arg self.ptr.*;
                            } else if (comptime T == *ctx.T) {
                                break :arg self.ptr;
                            } else if (comptime T == Ctx) {
                                break :arg C;
                            } else {
                                break :arg if (comptime ctx.parent != null) self.parent.get(T);
                            }
                        } else {
                            break :arg self;
                        }
                    }});
                } else {
                    const f = AnyFn.init(ff);
                    if (comptime @typeInfo(f.GetReturnType()) == .ErrorUnion) {
                        if (@call(.always_inline, comptime f.ptr(), args_tuple)) |r| {
                            return r;
                        } else |err| {
                            return self.handleError(f.GetReturnTypeStripError(), err);
                        }
                    } else {
                        return @call(.always_inline, comptime f.ptr(), args_tuple);
                    }
                }
            }

            pub fn callExt(self: Self, comptime ff: anytype, L: anytype, R: anytype) AnyFn.init(ff).GetReturnTypeStripError() {
                const Args = std.meta.ArgsTuple(@TypeOf(ff));
                var args: Args = undefined;

                comptime var i: usize = 0;
                inline for (std.meta.fields(@TypeOf(L)), 0..) |_, ii| {
                    args[i] = L[ii];
                    comptime i += 1;
                }

                comptime var Fields = std.meta.fields(Args);
                comptime var Last = Fields.len - R.len;
                inline while (i < Last) {
                    args[i] = self.get(Fields[i].type);
                    comptime i += 1;
                }
                inline for (std.meta.fields(@TypeOf(R)), 0..) |_, ii| {
                    args[i] = R[ii];
                    comptime i += 1;
                }
                if (comptime i != Fields.len) {
                    @compileError("Not all args set!");
                }

                return self.callWithArgs(ff, args);
            }

            pub fn callWithArgs(self: Self, comptime ff: anytype, args: anytype) AnyFn.init(ff).GetReturnTypeStripError() {
                const f = AnyFn.init(ff);
                if (comptime @typeInfo(f.GetReturnType()) == .ErrorUnion) {
                    if (@call(.always_inline, comptime f.ptr(), args)) |r| {
                        return r;
                    } else |err| {
                        return self.handleError(f.GetReturnTypeStripError(), err);
                    }
                } else {
                    return @call(.always_inline, comptime f.ptr(), args);
                }
            }

            pub fn handleError(_: Self, comptime RT: type, err: anytype) RT {
                std.log.err("{} from  {s}", .{ err, ctx.printCtxStack() });
                unreachable;
            }

            pub fn get(self: Self, comptime T: type) T {
                if (comptime !ctx.has(T)) {
                    @compileError(@typeName(T) ++ " not found!");
                }

                if (comptime @typeInfo(T) == .Struct and @hasDecl(T, "metaArg")) {
                    return T.metaArg(self);
                }

                if (comptime ctx.thisHas(T)) {
                    return self.getFromField(T);
                }

                const info = @typeInfo(ctx.T).Struct;
                inline for (info.fields) |f| {
                    if (comptime ctx.push(f.type).thisHas(T)) {
                        return self.push(&@field(self.ptr, f.name)).getFromField(T);
                    }
                }

                if (comptime ctx.parent != null) {
                    return self.parent.get(T);
                } else {
                    @compileError(@typeName(T) ++ " not found!");
                }
            }

            pub fn getFromField(self: Self, comptime T: type) T {
                if (comptime T == ctx.T) {
                    return self.ptr.*;
                } else if (comptime T == *ctx.T) {
                    return self.ptr;
                }

                //Exports
                if (comptime @typeInfo(ctx.T) == .Struct and @hasDecl(ctx.T, "Exports")) {
                    comptime var fields = std.meta.fields(ctx.T);
                    inline for (ctx.T.Exports) |e| {
                        comptime var index = std.meta.fieldIndex(ctx.T, e).?;
                        comptime var name = fields[index].name;
                        if (comptime ctx.push(fields[index].type).thisHas(T)) {
                            return self.push(&@field(self.ptr, name)).getFromField(T);
                        }
                    }
                }

                if (comptime @typeInfo(ctx.T) == .Struct and @hasDecl(ctx.T, "metaGet")) {
                    if (comptime ctx.T.metaHas(ctx, T)) {
                        return ctx.T.metaGet(self, T);
                    }
                }

                @compileError("must return");
            }

            pub fn fillTuple(self: Self, comptime T: type) T {
                var t: T = undefined;
                inline for (std.meta.fields(T), 0..) |f, i| {
                    t[i] = self.get(f.type);
                }
                return t;
            }

            pub fn fromType(comptime T: type) Ctx {
                return Ctx{ .T = T };
            }

            pub fn erase(self: Self) EState {
                return EState.init(self);
            }
            pub inline fn run(self: Self) void {
                self.initInstance();
                self.tickInstance();
                self.deinitInstance();
            }
        };
    }
    pub fn printCtxStack(comptime ctx: Ctx) []const u8 {
        if (comptime ctx.parent == null) {
            return @typeName(ctx.T);
        } else {
            comptime var trace = printCtxStack(ctx.parent.?.*) ++ "\n| " ++ @typeName(ctx.T);
            return trace;
        }
    }
    pub fn thisHas(comptime ctx: Ctx, comptime T: type) bool {
        if (comptime T == ctx.T or T == *ctx.T) {
            return true;
        }

        if (comptime @typeInfo(ctx.T) == .Struct and @hasDecl(ctx.T, "Exports")) {
            const fields = std.meta.fields(ctx.T);
            inline for (ctx.T.Exports) |e| {
                if (std.meta.fieldIndex(ctx.T, e)) |index| {
                    if (comptime ctx.push(fields[index].type).thisHas(T)) {
                        return true;
                    }
                }
            }
        }

        if (comptime @typeInfo(ctx.T) == .Struct and @hasDecl(ctx.T, "metaHas")) {
            return ctx.T.metaHas(ctx, T);
        }
        return false;
    }

    pub fn has(comptime ctx: Ctx, comptime T: type) bool {
        if (comptime @typeInfo(T) != .Pointer and @typeInfo(T) == .Struct and @hasDecl(T, "metaArg")) {
            return true;
        }

        if (comptime ctx.thisHas(T)) {
            return true;
        }

        const info = @typeInfo(ctx.T).Struct;
        inline for (info.fields) |f| {
            if (comptime ctx.push(f.type).thisHas(T)) {
                return true;
            }
        }
        if (comptime ctx.parent) |p| {
            return p.has(T);
        } else {
            return false;
        }
    }
    pub fn push(comptime ctx: Ctx, comptime T: type) Ctx {
        comptime var Tmp = struct {
            const c = Ctx{ .parent = ctx.parent, .T = ctx.T };
        };
        return Ctx{
            .parent = &Tmp.c,
            .T = T,
        };
    }
    pub fn CtxByType(comptime ctx: Ctx, comptime T: type) Ctx {
        if (comptime ctx.thisHas(T)) {
            return ctx;
        } else if (comptime ctx.parent) |p| {
            return p.CtxByType(T);
        }
    }

    pub fn CtxRoot(comptime T: type) Ctx {
        return Ctx{
            .T = T,
        };
    }

    pub fn from(p: anytype) CtxRoot(std.meta.Child(@TypeOf(p))).Instance() {
        return CtxRoot(std.meta.Child(@TypeOf(p))).Instance(){
            .parent = {},
            .ptr = p,
        };
    }
};

pub const ECtx = struct {
    ptr: *anyopaque,
    fun: fn (*anyopaque) void,
    pub fn init(comptime ctx: Ctx, comptime f: AnyFn, ptr: *ctx.T) @This() {
        const fun = struct {
            pub fn run(p: *anyopaque) void {
                const ff = f;

                ctx.call(ff, @as(*ctx.T, @ptrCast(@alignCast(p))));
            }
        }.run;

        return @This(){
            .ptr = @as(*anyopaque, @ptrCast(ptr)),
            .fun = fun,
        };
    }

    pub fn run(self: @This()) void {
        self.fun(self.ptr);
    }
};

fn getFieldEnum(comptime T: type, comptime name: []const u8) std.meta.FieldEnum(T) {
    comptime @setEvalBranchQuota(10000);
    return @as(std.meta.FieldEnum(T), @enumFromInt(std.meta.fieldIndex(T, name).?));
}

pub fn State(comptime Systems: anytype) type {
    const T = toTuple(Systems);
    // const Exports = std.meta.fieldNames(T);
    return struct {
        const Self = @This();
        pub const Exports = .{"data"};
        data: T,

        pub inline fn metaInit(ins: anytype) !void {
            var this = ins.get(*@This());
            ins.push(&this.data).initFields();
        }
        pub inline fn metaTick(ins: anytype) !void {
            var this = ins.get(*@This());
            ins.push(&this.data).tickFields();
        }
        pub inline fn metaDeinit(ins: anytype) !void {
            var this = ins.get(*@This());
            ins.push(&this.data).deinitFields();
        }

        pub fn get(self: *Self, comptime TT: type) TT {
            return Ctx.from(&self.data).get(TT);
        }

        pub fn metaGet(ins: anytype, comptime TT: type) TT {
            var this = ins.get(*@This());
            return ins.push(&this.data).get(TT);
        }

        pub fn metaHas(comptime _: Ctx, comptime TT: type) bool {
            return Ctx.CtxRoot(T).has(TT);
        }
    };
}
//@TODO zero sized types break ctx

pub fn toTuple(comptime Systems: anytype) type {
    comptime var fields: []const std.builtin.Type.StructField = &.{};

    inline for (Systems, 0..) |s, i| {
        const SType = if (comptime @TypeOf(s) == type) s else CallFn(s);

        var num_buf: [128]u8 = undefined;
        const f = std.builtin.Type.StructField{
            .name = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch unreachable,
            .type = SType,
            .is_comptime = false,
            .default_value = null,
            .alignment = 0,
        };

        fields = fields ++ &[_]std.builtin.Type.StructField{f};
    }

    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .decls = &.{},
            .fields = fields,
            .is_tuple = true,
        },
    });
}

pub fn OnInit(comptime T: type) type {
    return struct {
        const Self = @This();
        u: u8 = 0,
        state: T = undefined,
        pub fn metaInit(ins: anytype) !void {
            var this = ins.get(*@This());
            ins.push(&this.state).run();
        }
    };
}

pub fn CallFn(comptime f: anytype) type {
    if (@typeInfo(@TypeOf(f)) != .Fn) {
        @compileError("Expected a Function, got " ++ @typeName(@TypeOf(f)));
    }
    return struct {
        const Self = @This();
        const Args = std.meta.ArgsTuple(@TypeOf(f));
        a: u8 = 0,

        pub inline fn tick(comptime ctx: Ctx, ins: ctx.Instance()) !void {
            if (comptime AnyFn.init(f).GetReturnTypeStripError() != void) {
                var rt = ins.get(*AnyFn.init(f).GetReturnTypeStripError());
                rt.* = ins.call(f);
            } else {
                ins.call(f);
            }
        }
    };
}

pub const EState = struct {
    const Self = @This();
    const max_stack_size = 32;

    data: [@sizeOf(*anyopaque) * 32]u8 = undefined,

    pub fn init(ins: anytype) EState {
        var self: EState = undefined;
        std.mem.copy(u8, &self.data, std.mem.asBytes(&ins));
        return self;
    }

    pub fn as(self: Self, comptime T: type) T {
        return std.mem.bytesToValue(T, self.data[0..@sizeOf(T)]);
    }
};

pub fn OnFieldChange(comptime T: type, comptime field: std.meta.FieldEnum(T), comptime SS: anytype) type {
    return struct {
        lv: std.meta.fieldInfo(T, field).type = undefined,
        state: SS = undefined,
        pub fn metaInit(ins: anytype) !void {
            var t = ins.get(*T);
            ins.ptr.lv = @field(t, std.meta.fieldInfo(T, field).name);

            ins.push(&ins.ptr.state).initInstance();
        }
        pub inline fn metaTick(ins: anytype) !void {
            var t = ins.get(*T);
            if (ins.ptr.lv != @field(t, std.meta.fieldInfo(T, field).name)) {
                ins.push(&ins.ptr.state).tickInstance();
                ins.ptr.lv = @field(t, std.meta.fieldInfo(T, field).name);
            }
        }
        pub fn metaDeinit(ins: anytype) !void {
            ins.push(&ins.ptr.state).deinitInstance();
        }
    };
}

pub fn OnDeinit(System: anytype) type {
    return struct {
        state: System = undefined,
        pub fn metaInit(ins: anytype) !void {
            ins.push(&ins.ptr.state).initInstance();
        }

        pub fn metaDeinit(ins: anytype) !void {
            ins.push(&ins.ptr.state).tickInstance();
            ins.push(&ins.ptr.state).tickInstance();
        }
    };
}

pub fn ETable(comptime S: type) type {
    const fields = std.meta.fields(S);
    const len = fields.len;
    return struct {
        inits: [len]fn (e: EState, ptr: *anyopaque) void,
        deinits: [len]fn (e: EState, ptr: *anyopaque) void,
        ticks: [len]fn (e: EState, ptr: *anyopaque) void,

        pub fn init(comptime ctx: Ctx) @This() {
            var r: @This() = undefined;
            inline for (fields, 0..) |f, i| {
                const eins = EInstance(ctx.push(f.type));

                r.inits[i] = eins.init;
                r.deinits[i] = eins.deinit;
                r.ticks[i] = eins.tick;
            }
            return r;
        }
    };
}

pub fn EInstance(comptime ctx: Ctx) type {
    return struct {
        pub fn init(e: EState, ptr: *anyopaque) void {
            var ins = e.as(ctx.parent.?.Instance());
            ins.push(@as(*ctx.T, @ptrCast(@alignCast(ptr)))).initInstance();
        }
        pub fn deinit(e: EState, ptr: *anyopaque) void {
            var ins = e.as(ctx.parent.?.Instance());
            ins.push(@as(*ctx.T, @ptrCast(@alignCast(ptr)))).deinitInstance();
        }
        pub fn tick(e: EState, ptr: *anyopaque) void {
            var ins = e.as(ctx.parent.?.Instance());
            ins.push(@as(*ctx.T, @ptrCast(@alignCast(ptr)))).tickInstance();
        }
    };
}

pub fn Union(comptime U: type) type {
    return struct {
        const fields_names = std.meta.fieldNames(U);

        isSet: bool = false,
        ustate: U = undefined,
        estate: EState,
        etable: ETable(U) = undefined,

        pub fn metaInit(ins: anytype) !void {
            ins.ptr.estate = ins.erase();
            ins.ptr.etable = ETable(U).init(@TypeOf(ins).C);
        }

        pub fn set(self: *@This(), field: std.meta.Tag(U)) !void {
            var active = @intFromEnum(std.meta.activeTag(self.ustate));
            //@TODO make sure this is safe
            self.etable.deinits[active](self.estate, &self.ustate);

            inline for (std.meta.fields(std.meta.Tag(U))) |f| {
                if (f.value == @intFromEnum(field)) {
                    @field(self.ustate, f.name) = undefined;
                    self.etable.inits[@intFromEnum(field)](self.estate, @as(*anyopaque, @ptrCast(&self.ustate)));
                }
            }
            self.isSet = true;
        }

        pub fn get(self: *@This()) ?*U {
            if (!self.isSet) return null;
            return &self.ustate;
        }

        pub fn tick(self: *@This()) !void {
            if (self.isSet) {
                var active = std.meta.activeTag(self.ustate);
                //@TODO make sure this is safe
                self.etable.ticks[@intFromEnum(active)](self.estate, @as(*anyopaque, @ptrCast(&self.ustate)));
            }
        }

        pub fn deinit(self: *@This()) !void {
            if (self.isSet) {
                var active = std.meta.activeTag(self.ustate);
                //@TODO make sure this is safe
                self.etable.deinits[@intFromEnum(active)](self.estate, @as(*anyopaque, @ptrCast(&self.ustate)));
            }
        }
    };
}

pub fn Mux(comptime T: type) type {
    return struct {
        const Self = @This();
        data: T,
        select: std.meta.FieldEnum(T) = @as(std.meta.FieldEnum(T), @enumFromInt(0)),

        pub fn metaInit(ins: anytype) !void {
            ins.push(&ins.ptr.data).initFields();
        }
        pub inline fn metaTick(ins: anytype) !void {
            inline for (std.meta.fields(T), 0..) |f, i| {
                if (i == @intFromEnum(ins.ptr.select)) {
                    ins.push(&@field(ins.ptr.data, f.name)).tickInstance();
                }
            }
        }
        pub fn metaDeinit(ins: anytype) !void {
            ins.push(&ins.ptr.data).deinitFields();
        }

        pub fn get(self: *Self, comptime TT: type) TT {
            return Ctx.fromType(Self).from(.data).get(TT, &self.data);
        }

        pub fn is(self: *Self, e: std.meta.FieldEnum(T)) bool {
            return self.select == e;
        }

        pub fn OnSelect(comptime e: anytype, comptime TT: type) type {
            const S = struct {
                const On = @This();
                pub const InitFields = .{.state};

                state: TT = undefined,

                pub fn tick(mux: *Self, this: *@This(), t: TickFor(TT)) !void {
                    if (mux.select == e) {
                        t.tick(&this.state);
                    }
                }
            };

            return OnFieldChange(Self, .select, S);
        }

        pub fn OnDeselect(comptime e: anytype, comptime TT: type) type {
            const S = struct {
                const On = @This();
                pub const InitFields = .{.state};

                state: TT = undefined,
                on: bool = false,

                pub inline fn metaTick(ins: anytype) !void {
                    var mux = ins.get(*Self);
                    if (mux.select == e) {
                        ins.ptr.on = true;
                    } else if (ins.ptr.on) {
                        ins.push(&ins.ptr.state).tickInstance();
                        ins.ptr.on = false;
                    }
                }
            };

            return OnFieldChange(Self, .select, S);
        }
    };
}

pub fn TickFor(comptime T: type) type {
    return struct {
        estate: EState,
        fun: fn (EState, *anyopaque) void,
        pub fn metaArg(ins: anytype) @This() {
            const EIns = EInstance(@TypeOf(ins).C.push(T));

            return @This(){
                .estate = ins.erase(),
                .fun = EIns.tick,
            };
        }

        pub inline fn tick(self: @This(), field_ptr: anytype) void {
            self.fun(self.estate, @as(*anyopaque, @ptrCast(field_ptr)));
        }
    };
}

pub fn InitFor(comptime T: type) type {
    return struct {
        estate: EState,
        fun: fn (EState, *anyopaque) void,
        pub fn metaArg(ins: anytype) @This() {
            const EIns = EInstance(@TypeOf(ins).C.push(T));

            return @This(){
                .estate = ins.erase(),
                .fun = EIns.init,
            };
        }

        pub inline fn init(self: @This(), field_ptr: anytype) void {
            self.fun(self.estate, @as(*anyopaque, @ptrCast(field_ptr)));
        }
    };
}

pub fn DeinitFor(comptime T: type) type {
    return struct {
        estate: EState,
        fun: fn (EState, *anyopaque) void,
        pub fn metaArg(ins: anytype) @This() {
            const EIns = EInstance(@TypeOf(ins).C.push(T));

            return @This(){
                .estate = ins.erase(),
                .fun = EIns.deinit,
            };
        }

        pub inline fn deinit(self: @This(), field_ptr: anytype) void {
            self.fun(self.estate, @as(*anyopaque, @ptrCast(field_ptr)));
        }
    };
}

pub fn FromDo(comptime From: type, comptime Do: type) type {
    return struct {
        state: Do,

        pub fn metaInit(ins: anytype) !void {
            var f = ins.get(*From);
            ins.push(f).push(&ins.ptr.state).initInstance();
        }
        pub fn metaDeinit(ins: anytype) !void {
            var f = ins.get(*From);
            ins.push(f).push(&ins.ptr.state).deinitInstance();
        }
        pub fn metaTick(ins: anytype) !void {
            var f = ins.get(*From);
            ins.push(f).push(&ins.ptr.state).tickInstance();
        }
    };
}

pub fn Req(comptime Types: []const type) type {
    const T = std.meta.Tuple(Types);
    return struct {
        table: T,
        pub fn metaArg(ins: anytype) @This() {
            return @This(){
                .table = ins.fillTuple(T),
            };
        }

        pub fn get(self: @This(), comptime Q: type) Q {
            inline for (std.meta.fields(T), 0..) |f, i| {
                if (Q == f.type) {
                    return self.table[i];
                }
            }
        }
    };
}

pub fn ActiveOnField(comptime P: type, comptime tag: anytype, comptime value: anytype, comptime T: anytype) type {
    return struct {
        pub const InitFields = .{.state};
        state: T,

        pub inline fn metaTick(ins: anytype) !void {
            var p = ins.get(*P);
            if (@field(p, @tagName(tag)) == value)
                ins.push(&ins.ptr.state).tickInstance();
        }
    };
}

fn fn_with_ctx_param(comptime ctx: Ctx, i: i32, ins: ctx.Instance()) !void {
    std.debug.print("printing i from fn_with_ctx_param: {}\n", .{i});

    std.debug.print("calling print_i32 from fn_with_ctx_param\n", .{});
    ins.call(print_i32);
}

const MyApp = State(.{
    //add an allocator to state
    std.mem.Allocator,
    //set the allocator to testing allocator
    OnInit(CallFn(setAlloc)),
    //add an i32 to state
    i32,
    //initilize the i32 using setI32
    OnInit(CallFn(setI32)),
    //call fn_with_ctx_param
    fn_with_ctx_param,

    //State is similar to a div in html. You can nest them togather.
    State(.{
        Foo,
        addOneToFoo,
        Bar,
        appendFooToBar,
    }),
});

pub fn setAlloc(alloc: *std.mem.Allocator) void {
    alloc.* = std.testing.allocator;
}

pub fn setI32(a: *i32) void {
    a.* = 1;
}

const Foo = struct {
    a: usize = 0,
    b: usize = 10,

    pub fn tick(self: *@This()) void {
        std.debug.print("Foo {any}: {}\n", .{ @intFromPtr(self), self.a });
    }
};

fn addOneToFoo(foo: *Foo) void {
    foo.a += 1;
}

const Bar = struct {
    data: std.ArrayList(usize),

    pub fn init(alloc: std.mem.Allocator) @This() {
        return @This(){
            .data = std.ArrayList(usize).init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.data.deinit();
    }
};

fn appendFooToBar(foo: *Foo, bar: *Bar) !void {
    try bar.data.append(foo.a);
}

const builtin = @import("builtin");
fn ask_user() !i32 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    var buf: [10]u8 = undefined;

    try stdout.print("A number please: ", .{});

    const delimiter = if (comptime builtin.os.tag == .windows) '\r' else '\n';

    if (try stdin.readUntilDelimiterOrEof(buf[0..], delimiter)) |user_input| {
        if (comptime builtin.os.tag == .windows)
            _ = try stdin.readByte();
        return std.fmt.parseInt(i32, user_input, 10);
    } else {
        return @as(i32, 0);
    }
}

fn print_i32(i: i32) void {
    std.debug.print("{}\n", .{i});
}

test "Example" {
    var app: MyApp = undefined;

    //create a ctx instance
    Ctx.from(&app).run();
}
