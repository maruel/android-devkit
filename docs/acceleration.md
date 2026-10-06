# Hardware acceleration

The supported kernel is `5.15.71`.

| Device | Driver | Role |
| --- | --- | --- |
| `/dev/video0` | `pxp_v4l2_out` | PxP video output/overlay |
| `/dev/video1` | `mx6s-csi` | Camera capture |
| `/dev/dri/card0` | `Vivante_GCCore` | GPU |

The configured boards expose no hardware H.264 or JPEG codec device. Installed
Coda/VDOA module files alone do not establish codec support.

PxP accepts RGB and YUV output formats. Its composition/conversion path is not
validated. `v4l2-ctl --all` and `--get-fmt-video-out` crash against the PxP node;
avoid those commands there.

GStreamer provides `v4l2src`, `v4l2sink`, and software JPEG/OpenH264 elements.
Camera capture does not establish hardware codec support.
