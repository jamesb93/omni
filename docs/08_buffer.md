## Buffer

`Buffer` is a special construct that is implemented on a per-wrapper basis. It doesn't exist as a standalone omni `struct`, but it only works if the wrapper around omni (like [omnicollider]() and [omnimax]()) implement it. Its purpose is to deal with memory allocated from outside of omni, as it's the case with SuperCollider's or Max's own buffers. Check [here](11_writing_wrappers.md) for a description on how to write an omni wrapper (including the `Buffer` interface).

### *MyBuffer.omni*:
```nim
ins 2:
    "buffer"
    "speed" {1, 0, 10}

outs: 1

init:
    #One of the ins has to be used for omni to point at the specified external buffer.
    buffer = Buffer.new(input_num = 1)
    phase = 0.0

perform:
    scaled_rate = buffer.samplerate / samplerate
    
    sample:
        out1 = buffer[phase]
        phase += (in2 * scaled_rate)
        phase = phase % float(buffer.len)
```

### SuperCollider
After compiling the omni code with

    omnicollider MyBuffer.omni

the `Buffer` interface will work as a regular SuperCollider Buffer. For example:

```c++
b = Buffer.read(s, Platform.resourceDir +/+ "sounds/a11wlk01.wav");
{MyBuffer.ar(b, 1)}.play
```

### Max

After compiling the omni code with

    omnimax MyBuffer.omni

the `Buffer` interface will look like so: