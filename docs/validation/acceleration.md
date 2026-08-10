# Hardware-acceleration inventory

Runtime inspection of the validated target (`5.15.71`) found **no hardware
H.264 or JPEG codec device**. Installed Coda/VDOA module files and generic V4L2
mem2mem configuration do not establish a bound codec device: no VPU, JPEG, or
codec mem2mem `/dev/video*` node was enumerated.

`/dev/video0` is the i.MX PxP driver (`pxp_v4l2_out`). It advertises V4L2 video
output/overlay rather than capture or memory-to-memory encoding, and accepts
RGB and YUV output formats. It may accelerate display composition or conversion
only after its actual output path is separately tested; it is not evidence of
JPEG or H.264 acceleration. The target's `v4l2-ctl --all` and
`--get-fmt-video-out` segfault against that node, so do not use those commands
as a PxP test.

`/dev/dri/card0` is bound to `platform:Vivante_GCCore`. GStreamer provides
generic `v4l2src`/`v4l2sink` plus software JPEG and OpenH264 elements, but no
V4L2 H.264/JPEG encoder or decoder element. FFmpeg was not installed during the
inspection.

Camera capture acceptance is independent of codec support. Do not couple a
codec experiment to `/dev/video1` until a non-camera codec/mem2mem device is
enumerated and validated with a static test vector.
