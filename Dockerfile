FROM nvidia/cuda:11.0.3-cudnn8-runtime-ubuntu18.04

LABEL maintainer="Mindsync <docker@mindsync.ai>"

RUN chmod 1777 /tmp && chmod 1777 /var/tmp

ARG NB_USER="mindsync"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-eux", "-c"]

USER root

# ---- Miniforge installer ----
# Default values can be overridden at build time
# (ARGS are in lower case to distinguish them from ENV)
# Check https://github.com/conda-forge/miniforge/releases
# Conda version
ARG conda_version="4.9.2"
# Miniforge installer patch version
ARG miniforge_patch_number="7"
# Miniforge installer architecture
ARG miniforge_arch="x86_64"
# Package Manager and Python implementation to use (https://github.com/conda-forge/miniforge)
# - conda only: either Miniforge3 to use Python or Miniforge-pypy3 to use PyPy
# - conda + mamba: either Mambaforge to use Python or Mambaforge-pypy3 to use PyPy
ARG miniforge_python="Mambaforge"

# Miniforge archive to install
ARG miniforge_version="${conda_version}-${miniforge_patch_number}"
# Miniforge installer
ARG miniforge_installer="${miniforge_python}-${miniforge_version}-Linux-${miniforge_arch}.sh"
# Miniforge checksum
ARG miniforge_checksum="5a827a62d98ba2217796a9dc7673380257ed7c161017565fba8ce785fb21a599"
ARG PYTHON_VERSION=3.7

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER \
    CONDA_VERSION="${conda_version}" \
    MINIFORGE_VERSION="${miniforge_version}" \
# Import matplotlib the first time to build the font cache.
    DG_CACHE_HOME="/home/${NB_USER}/.cache/" \
    TENSORFLOW_WHL=tensorflow-2.4.1-cp37-cp37m-linux_x86_64.whl \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get -q update && \
    apt-get install -yq --no-install-recommends locales apt-utils && \
    locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8
 
# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

RUN apt-get -q update && \
    apt-get install -yq --no-install-recommends \
    cron \
    wget \
    ca-certificates \
    sudo \
    #locales \
    fonts-liberation \
    run-one \
# Install all OS dependencies for fully functional notebook server
    build-essential \
    vim-tiny \
    git \
    inkscape \
    libsm6 \
    libxext-dev \
    libxrender1 \
    lmodern \
    netcat \
# ---- nbconvert dependencies ----
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    # ----
    tzdata \
    unzip \
    nano-tiny \
# Install nvtop to monitor the gpu tasks
    cmake \
    libncurses5-dev \
    libncursesw5-dev \
    git \
# Install important packages and Graphviz
    htop \
    #apt-utils \
    iputils-ping \
    graphviz \
    libgraphviz-dev \
    openssh-client \
# ffmpeg for matplotlib anim & dvipng+cm-super for latex labels
    ffmpeg \
    dvipng \
    cm-super && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


# Create alternative for nano -> nano-tiny
RUN update-alternatives --install /usr/bin/nano nano /bin/nano-tiny 10

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc 

RUN git clone https://github.com/Syllo/nvtop.git /tmp/nvtop && \
    mkdir -p /tmp/nvtop/build && cd /tmp/nvtop/build && \
    (cmake .. -DNVML_RETRIEVE_HEADER_ONLINE=True 2> /dev/null || echo "cmake was not successful") && \
    (make 2> /dev/null || echo "make was not successful") && \
    (make install 2> /dev/null || echo "make install was not successful") && \
    cd /tmp && rm -rf /tmp/nvtop

# Create NB_USER with name mindsync user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd
#    fix-permissions $HOME && \
#    fix-permissions $CONDA_DIR

USER $NB_UID
# Setup work directory for backward-compatibility
#RUN mkdir "/home/${NB_USER}/work" && \
#    fix-permissions "/home/${NB_USER}"

RUN mkdir "/home/${NB_USER}/work"

# Install conda as mindsync and check the sha256 sum provided on the download site
WORKDIR /tmp

# Prerequisites installation: conda, mamba, pip, tini
RUN wget --quiet "https://github.com/conda-forge/miniforge/releases/download/${miniforge_version}/${miniforge_installer}" && \
    echo "${miniforge_checksum} *${miniforge_installer}" | sha256sum --check && \
    /bin/bash "${miniforge_installer}" -f -b -p $CONDA_DIR && \
    rm "${miniforge_installer}" && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [ ! $PYTHON_VERSION = 'default' ]; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes \
    "conda=${CONDA_VERSION}" \
    'pip' \
    'tini=0.18.0' && \
    conda update --all --quiet --yes && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn


# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
RUN conda install --quiet --yes \
    'notebook=6.2.0' \
    'jupyterhub=1.3.0' \
    'jupyterlab=3.0.12' \
    'beautifulsoup4=4.9.*' \
    'conda-forge::blas=*=openblas' \
    'bokeh=2.3.*' \
    'bottleneck=1.3.*' \
    'cloudpickle=1.6.*' \
    'cython=0.29.*' \
    'dask=2021.3.*' \
    'dill=0.3.*' \
    'h5py=3.1.*' \
    'ipywidgets=7.6.*' \
    'ipympl=0.6.*'\
    'matplotlib-base=3.3.*' \
    'numba=0.53.*' \
    'numexpr=2.7.*' \
    'pandas=1.2.*' \
    'patsy=0.5.*' \
    'protobuf=3.15.*' \
    'pytables=3.6.*' \
    'scikit-image=0.18.*' \
    'scikit-learn=0.24.*' \
    'scipy=1.6.*' \
    'seaborn=0.11.*' \
    'sqlalchemy=1.4.*' \
    'statsmodels=0.12.*' \
    'sympy=1.7.*' \
    'vincent=0.4.*' \
    'widgetsnbextension=3.5.*'\
    'xlrd=2.0.*' \
    pyyaml \
    mkl \
    mkl-include \
    setuptools \
    cmake \
    cffi \
    typing && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    jupyter lab clean

# Install facets which does not have a pip or conda package at the moment
RUN git clone https://github.com/PAIR-code/facets.git && \
    jupyter nbextension install facets/facets-dist/ --sys-prefix && \
    rm -rf /tmp/facets

RUN MPLBACKEND=Agg python -c "import matplotlib.pyplot"
    #fix-permissions "/home/${NB_USER}"

WORKDIR $HOME

COPY --chown="${NB_UID}:${NB_GID}" tensorflow-whl/gpu/${TENSORFLOW_WHL} "${HOME}/${TENSORFLOW_WHL}"

RUN pip install --upgrade pip && \
    pip install --no-cache-dir graphviz==0.11 \
    "${HOME}/${TENSORFLOW_WHL}" \
    keras \
    ipyleaflet \
    "plotly>=4.14.3" \
    "ipywidgets>=7.5" \
    jupyterlab-drawio \
    jupyter_contrib_nbextensions \
    jupyter_nbextensions_configurator \
    rise && \
    rm -rf "${HOME}/${TENSORFLOW_WHL}"

RUN jupyter nbextension enable --py --sys-prefix ipyleaflet && \
    jupyter labextension install jupyterlab-plotly \
                                 @jupyter-widgets/jupyterlab-manager \
                                 plotlywidget \
                                 @ijmbarr/jupyterlab_spellchecker

#RUN fix-permissions "${CONDA_DIR}" "/home/${NB_USER}"

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/

# Install customizations
COPY --chown="${NB_UID}:${NB_GID}" custom /home/${NB_USER}/.jupyter/custom
COPY --chown="${NB_UID}:${NB_GID}" custom.py /usr/local/bin/custom.py

# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root

# Prepare upgrade to JupyterLab V3.0 #1205
RUN sed -re "s/c.NotebookApp/c.ServerApp/g" \
    /etc/jupyter/jupyter_notebook_config.py > /etc/jupyter/jupyter_server_config.py && \
    fix-permissions /etc/jupyter/ && \
    chmod a+rx /usr/local/bin/custom.py \
               /usr/local/bin/start-notebook.sh \
               /usr/local/bin/start.sh \
               /usr/local/bin/start-singleuser.sh

RUN rm -rf /tmp/*

USER $NB_UID

RUN rm -rf "${HOME}/.cache/*"

EXPOSE 8888
WORKDIR "${HOME}/work"
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

