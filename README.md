# 8086 Assembly Interpreter

_an absurdly simple 8086 interpreter for my school’s assembly entrance exam evaluation system._

## THIS PROJECT IS STILL IN CONSTRUCTION...

### What should you use it for

As the name implies, this projet _interpets_ simple assembly code. It does not, by any means emulate a full-on working 8086 CPU, neither do this its purpose.

It can be used to run the most basic asm commands and doesn't allow for much interesting behaviours.

I suspect it might be very fraglie (even though there are unit tests), so if you found a bug and want to fix it, feel free to open a pull request!

### how to run

Make sure you have zig v0.14.1 installed, and run
```bash
zig build run
```

or
```bash
zig build test
```
to run the tests
