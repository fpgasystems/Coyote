# Build from the Coyote checkout (.dockerignore at the checkout root leaves the synthesis checkpoints
# and build folders out of the context):
#   docker build -f sim/container/Dockerfile -t coyote-sim .
# Run:
#   docker run --rm coyote-sim [host program arguments]
FROM ubuntu:22.04
ARG EXAMPLE=examples/01_hello_world
COPY sim/container/install.sh /opt/coyote/sim/container/
COPY sim/vl/install_verilator.sh sim/vl/verilator.env /opt/coyote/sim/vl/
RUN /opt/coyote/sim/container/install.sh --deps
COPY . /opt/coyote
RUN /opt/coyote/sim/container/install.sh /opt/coyote /opt/coyote/${EXAMPLE}/hw /work /opt/coyote/${EXAMPLE}/sw
# PATH is for an interactive shell in the image.
ENV PATH=/opt/verilator/bin:$PATH
ENTRYPOINT ["/opt/coyote/sim/container/run.sh"]
