const std = @import("std");

pub fn ArgsTupleSkipN(comptime Function: type, comptime N: usize) type {
    const info = @typeInfo(Function);
    if (info != .Fn)
        @compileError("ArgsTuple expects a function type");

    const function_info = info.Fn;
    if (function_info.is_var_args)
        @compileError("Cannot create ArgsTuple for variadic function");

    var argument_field_list: [function_info.args.len - N]type = undefined;
    inline for (function_info.args[N..]) |arg, i| {
        const T = arg.arg_type.?;
        argument_field_list[i] = T;
    }

    return CreateUniqueTuple(argument_field_list.len, argument_field_list);
}

fn CreateUniqueTuple(comptime N: comptime_int, comptime args: [N]type) type {
    var tuple_fields: [args.len]std.builtin.Type.StructField = undefined;
    inline for (args) |a, i| {
        @setEvalBranchQuota(10_000);
        var num_buf: [128]u8 = undefined;

                tuple_fields[i] = .{
                .name = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch unreachable,
                .field_type = a,
                .default_value = null,
                .is_comptime = false,
                .alignment = if (@sizeOf(a) > 0) @alignOf(a) else 0,
            };
    }

    return @Type(.{
        .Struct = .{
            .is_tuple = true,
            .layout = .Auto,
            .decls = &.{},
            .fields = &tuple_fields,
        },
    });
}