FROM python:3.8-alpine3.10

# set id environment variables
ENV PUID=1002
ENV PGID=102

# configure user and group
ARG user=abc
ARG home=/home/$user
RUN addgroup \
    --gid ${PGID} \
    -S docker
RUN adduser \
    --uid ${PUID} \
    --disabled-password \
    --gecos "" \
    --home $home \
    --ingroup docker \
    $user

# update apk repo
RUN echo "http://dl-4.alpinelinux.org/alpine/v3.10/main" >> /etc/apk/repositories && \
    echo "http://dl-4.alpinelinux.org/alpine/v3.10/community" >> /etc/apk/repositories

# install chromedriver
RUN apk update
RUN apk --no-cache add chromium chromium-chromedriver bash curl sed grep nano netcat-openbsd iputils nmap-scripts git

# set busybox permission so it can be run without root - for traceroute
RUN setcap cap_net_raw+ep /bin/busybox

# upgrade pip
RUN pip install --upgrade pip

# install selenium
RUN pip install selenium

#VOLUME /app/cfg
#VOLUME /app/output

# need to change this to properly use persistent files for cfg 
#COPY ./static_status /app
RUN cd /home/$user
RUN git clone https://github.com/h0me5k1n/static_status.git
RUN mkdir /app
RUN cp -r ./static_status/* /app/ && rm -R ./static_status/*
RUN chown abc:docker /app -R

WORKDIR /app

# set uid and gid
USER abc:docker
#run "id"

ENTRYPOINT ["./status.sh"]
CMD ["loud"] 

