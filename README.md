# A Declartive Zig Framework

An experimental Zig library that allows to build applications declarativaly (React like).


## Why?

- Automatic Constructors/Deconstrutors
- Call functions without having to provide it's arguments
- Comptime introspection of the program's context
  - Allows generic allocators without needing to erase it's type
- Pass partial programs as comptime arguments.

## Example

```zig
const MyApp = State(.{
    //add an allocator to state
    std.mem.Allocator,

    //set the allocator to testing allocator
    OnInit(CallFn(setAlloc)),

    //add an i32 to state
    i32,

    //initilize the i32 using setI32
    OnInit(CallFn(setI32)),

    //set i32 from stdin
    print_i32,

    //State is similar to a div in html. You can nest them togather.
    
    State(.{
        Foo,
        addOneToFoo,
        Bar,
        appendFooToBar,
    }),
});

pub fn setAlloc() std.mem.Allocator {
    return std.testing.allocator;
}

pub fn setI32() i32 {
    return 1;
}

const Foo = struct {
    a: usize = 0,
    b: usize = 10,

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
```


