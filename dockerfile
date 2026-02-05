FROM centos:7

# Point CentOS 7 repos to vault.centos.org (EOL mirrors were removed)
RUN sed -i -e 's/^mirrorlist=/#mirrorlist=/g' /etc/yum.repos.d/CentOS-*.repo && \
    sed -i -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo && \
    yum clean all && \
    yum -y makecache

# Install rpmbuild and common helpers/tools
RUN yum -y install \
      rpm-build \
      rpmdevtools \
      redhat-rpm-config \
      yum-utils \
      rpmlint \
      gcc \
      make \
      git \
      tar \
      which \
      java-11-openjdk-devel \
    && yum clean all

# Set up the standard rpmbuild tree for root
RUN rpmdev-setuptree
WORKDIR /root/rpmbuild
