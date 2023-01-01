const std = @import("std");

threadlocal var P : f32 = 10;

const A = struct { 
    a: f32 = 1,
};

fn foo(comptime a: *A, b: f32) f32 {
    return a.a + b + P;
}

const Arg = struct {
    T: type,
    is_comptime: bool,
};



test "FOO" {
    const T = std.meta.Tuple(&.{struct{}});
    var t= T{.{}};
    var p = &@field(t, "0");
    _ = p;
}