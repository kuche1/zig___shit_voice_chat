
// zig build-exe cable.zig --library c --library rt --library jack --library pthread --library portaudio && ./cable listen
// native x86_64-native x86_64-native-gnu


const std = @import("std");
const echo = std.debug.print;
const print = std.io.getStdOut().writer().print;
const net = std.net;

const c = @cImport({
    @cInclude("portaudio.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("math.h");
    @cInclude("string.h");
});







const SAMPLE_RATE = 190_000;
const FRAMES_PER_BUFFER = 256;

pub fn main() !u8 {

    var err: c.PaError = undefined;

    err = c.Pa_Initialize();
    if(err != c.paNoError) return error.Pa_Initialize;
    
    defer{
        err = c.Pa_Terminate();
        if(err != c.paNoError) echo("error on terminate: {s}\n", .{c.Pa_GetErrorText(err)});
    }

    echo("args: {s}\n", .{std.os.argv});

    const argv = std.os.argv;

    if(argv.len <= 1){
        try print("Too few arguments\n", .{});
        return 1;
    }
    
    const action = argv[1];

    if(c.strcmp(action, "listen") == 0){
        try accept_next_connection(0);
    }else if(c.strcmp(action, "connect") == 0){
        try establish_new_connection(0);
    }else{
        try print("Bad action: {s}\n", .{action});
        return 1;
    }

    return 0;
}








fn accept_next_connection(nothing: u32) !void {

    var host = net.StreamServer.init(.{.reuse_address=true});
    defer host.deinit();

    const addr = "0.0.0.0";
    const port = 6969;
    const parsed_addr = try net.Address.parseIp(addr, port);
    try host.listen(parsed_addr);

    const con = try host.accept();
    const adr = con.address;
    echo("connection from {}\n", .{adr});

    var stream = con.stream; // TODO change this to const

    const thr_recv = try std.Thread.spawn(receive_and_play, &stream);
    const thr_send = try std.Thread.spawn(record_and_send, &stream);

    thr_recv.wait();
    thr_send.wait();
    
}




fn establish_new_connection(nothing: u32) !void {

    const port = 6969;
    const addr = "127.0.0.1";
    const parsed_addr = try net.Address.parseIp(addr, port);
    
    var stream: std.net.Stream = undefined;
    while(true){
        stream = std.net.tcpConnectToAddress(parsed_addr) catch|err|{
            echo("unable to connect: {} ; retrying\n", .{err});
            std.time.sleep(5_000_000_000);
            continue;
        };
        break;
    }
    defer stream.close();

    const thr_recv = try std.Thread.spawn(receive_and_play, &stream);
    const thr_send = try std.Thread.spawn(record_and_send, &stream);

    thr_recv.wait();
    thr_send.wait();
    
}








fn receive_and_play(net_stream: *std.net.Stream) !void {

    var err: c.PaError = undefined;
    var stream: ?*c.PaStream = undefined;

    echo("=========================== default output: {} ; count: {}\n", .{c.Pa_GetDefaultOutputDevice(), c.Pa_GetDeviceCount()});

    // Open an audio I/O stream.
    err = c.Pa_OpenDefaultStream( &stream,
                                0,          // 2 - stereo input ; 1 - mono ; 0 - no input channels
                                1,          // 2 - stereo output
                                c.paFloat32,  // 32 bit floating point output
                                SAMPLE_RATE, // sample rate - 44100, 48000, ...
                                FRAMES_PER_BUFFER,        // frames per buffer, i.e. the number
                                            //       of sample frames that PortAudio will
                                            //       request from the callback. Many apps
                                            //       may want to use
                                            //       paFramesPerBufferUnspecified, which
                                            //       tells PortAudio to pick the best,
                                            //       possibly changing, buffer size.
                                null, // this is your callback function
                                null ); // This is a pointer that will be passed to
                                         //          your callback

    if(err != c.paNoError) return error.Pa_OpenDefaultStream;

    defer{
        err = c.Pa_CloseStream(stream);
        if(err != c.paNoError) echo("error in Pa_CloseStream\n", .{});
    }

    err = c.Pa_StartStream(stream);
    if(err != c.paNoError) return error.Pa_StartStream;

    defer{
        err = c.Pa_StopStream(stream);
        if(err != c.paNoError) echo("error in Pa_StopStream\n", .{});
    }


    var buf: [FRAMES_PER_BUFFER]f32 = undefined;

    while(true){

        var data: [4]u8 = undefined;

        for(buf)|_, ind|{
            const red = net_stream.read(data[0..]) catch return error.net_stream_read;
            var fl_data = @bitCast(f32, data);
            buf[ind] = fl_data;
        }

        err = c.Pa_WriteStream(stream, &buf, FRAMES_PER_BUFFER);
        //echo("write err: {}\n", .{err});
        
    }
    
    
}


fn record_and_send(net_stream: *std.net.Stream) !void {

    var err: c.PaError = undefined;
    var stream: ?*c.PaStream = undefined;

    // Open an audio I/O stream.
    err = c.Pa_OpenDefaultStream( &stream,
                                1,          // 2 - stereo input ; 1 - mono ; 0 - no input channels
                                0,          // 2 - stereo output
                                c.paFloat32,  // 32 bit floating point output
                                SAMPLE_RATE, // sample rate - 44100, 48000, ...
                                FRAMES_PER_BUFFER,        // frames per buffer, i.e. the number
                                            //       of sample frames that PortAudio will
                                            //       request from the callback. Many apps
                                            //       may want to use
                                            //       paFramesPerBufferUnspecified, which
                                            //       tells PortAudio to pick the best,
                                            //       possibly changing, buffer size.
                                null, // this is your callback function
                                null ); // This is a pointer that will be passed to
                                         //          your callback

    if(err != c.paNoError) return error.Pa_OpenDefaultStream;

    defer{
        err = c.Pa_CloseStream(stream);
        if(err != c.paNoError) echo("error in Pa_CloseStream\n", .{});
    }

    err = c.Pa_StartStream(stream);
    if(err != c.paNoError) return error.Pa_StartStream;

    defer{
        err = c.Pa_StopStream(stream);
        if(err != c.paNoError) echo("error in Pa_StopStream\n", .{});
    }


    var buf: [FRAMES_PER_BUFFER]f32 = undefined;

    while(true){

        err = c.Pa_ReadStream(stream, &buf, FRAMES_PER_BUFFER);
        //echo("read err: {}\n", .{err});

        for(buf)|data|{
            const to_send = @bitCast([4]u8, data);
            _ = net_stream.write(to_send[0..]) catch {
                return error.net_stream__write;
            };
        }
        
    }

}
