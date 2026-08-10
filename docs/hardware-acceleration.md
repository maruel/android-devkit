# Pico i.MX7 hardware-acceleration inventory

Runtime inspection of the validated target (`5.15.71`) found no hardware H.264
or JPEG codec device. The installed Coda/VDOA module files and generic V4L2
mem2mem configuration do not establish a bound codec device; no VPU, JPEG, or
codec mem2mem `/dev/video*` node was present.

`/dev/video0` is the i.MX PxP driver (`pxp_v4l2_out`) and advertises V4L2 video
output/overlay, not capture or memory-to-memory encoding. It accepts RGB and
YUV output formats, so it may accelerate display composition/conversion only
when its concrete output path is separately tested. It is not evidence of JPEG
or H.264 acceleration. `v4l2-ctl --all` and `--get-fmt-video-out` currently
make the target's `v4l2-ctl` process segfault against that node; do not use them
as a PxP validation method.

`/dev/dri/card0` is bound to `platform:Vivante_GCCore`. GStreamer has generic
`v4l2src`/`v4l2sink` plus software JPEG and OpenH264 elements, but no V4L2
H.264/JPEG encoder or decoder element. FFmpeg is not installed on the target.

Camera acceptance was established independently; do not couple codec testing
to camera capture until a non-camera codec/mem2mem node is enumerated and
validated with a static test vector.
