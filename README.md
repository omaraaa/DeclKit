Experimental framework using zig's comptime.


# Example

```zig
const std = @import("std");
const ctx = @import("./ctx.zig");


const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn setAlloc(gpa: *GPA) std.mem.Allocator {
    return gpa.allocator();
}
const MyApp = ctx.State(.{
    GPA,
    ctx.OnInit(ctx.CallFn(setAlloc)),

    //You can create nested states
    ctx.State(.{
        Foo, addOneToFoo, Bar, appendFooToBar,

        //Same state again
        ctx.State(.{
            Foo, addOneToFoo, Bar, appendFooToBar,
        }),
    }),
});

const Foo = struct {
    a: usize = 0,

    pub fn tick(self: *@This()) void {
        std.debug.print("Foo {any}: {}\n", .{ @ptrToInt(self), self.a });
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

pub fn main() anyerror!void {
    var app: MyApp = undefined;

    //create a ctx instance
    var ctx = ctx.Ctx.init(&app);

    ctx.initInstance();
    defer ctx.deinitInstance();
    
    //running the app state 3 times
    ctx.tickInstance();
    ctx.tickInstance();
    ctx.tickInstance();
}
```
