
FROM ubuntu:22.04
ENV HOME /root
WORKDIR $HOME
RUN apt update
# setup Node.js
RUN apt install -y npm curl
RUN npm install -g n
RUN n lts
# setup python3-venv
RUN apt install -y python3-venv
# build ruby 3.1.2-refgraph
RUN apt install -y \
  autoconf \
  bison \
  clang \
  libffi-dev \
  libreadline-dev \
  libssl-dev \
  rbenv \
  ruby
RUN echo 'eval "$(rbenv init -)"' >> $HOME/.bashrc
COPY . $HOME/ruby-refgraph
WORKDIR $HOME/ruby-refgraph
RUN autoconf
RUN autoreconf --install
RUN mkdir build
WORKDIR $HOME/ruby-refgraph/build
RUN CC=clang ../configure --prefix $(rbenv root)/versions/3.1.2-clang-refgraph --disable-install-doc
RUN make install
RUN rbenv global 3.1.2-clang-refgraph
# activate refgraph extensions
WORKDIR $HOME/ruby-refgraph/refgraph
RUN eval "$(rbenv init -)" && \
    gem install bundler && \
    bin/setup && \
    bundle exec rake build && \
    gem install pkg/refgraph-0.1.0.gem
# install benchmark dependencies
WORKDIR $HOME/ruby-refgraph/refgraph/benchmarks/babel
RUN npm install
# setup figure generator
WORKDIR $HOME/ruby-refgraph/refgraph/experiment
RUN python3 -m venv venv --upgrade-deps
RUN venv/bin/pip install matplotlib==3.6.1
# entrypoint
ENV RUBY_REFGRAPH_BENCHMARK_DIR $HOME/ruby-refgraph/refgraph/benchmarks
ENV RUBY_REFGRAPH_BENCHMARK_NO_PDFJS TRUE
WORKDIR $HOME
CMD /bin/bash
