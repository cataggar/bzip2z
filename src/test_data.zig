pub fn repeat(comptime pattern: []const u8, comptime count: usize) *const [pattern.len * count]u8 {
    return comptime blk: {
        const data: [count][pattern.len]u8 = @splat(pattern[0..pattern.len].*);
        break :blk @ptrCast(&data);
    };
}
