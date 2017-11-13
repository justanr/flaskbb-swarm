FROM python:3.6-slim as REQS
MAINTAINER alec reiter <alecreiter@gmail.com>
RUN apt-get update -qy && \
    apt-get install -qyy \
        -o APT::Install-Recommends=False \
        -o APT::Install-Suggests=False \
        gcc \
        build-essential
RUN pip install wheel
ENV WHEELHOUSE=/wheelhouse
ENV PIP_WHEEL_DIR=/wheelhouse
ENV PIP_FIND_LINKS=/wheelhouse
COPY ./flaskbb/requirements.txt /requirements.txt
RUN sed -i '$d' requirements.txt && pip wheel -r requirements.txt
COPY ./scripts/requirements.txt /requirements.txt
RUN pip wheel -r requirements.txt


FROM python:3.6-slim as APP
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
RUN useradd -r flaskbb
MAINTAINER alec reiter <alecreiter@gmail>
COPY --from=REQS /wheelhouse /wheelhouse
WORKDIR /var/run/flaskbb
COPY ./flaskbb .
RUN chown -R flaskbb:flaskbb /var/run/flaskbb
RUN pip install --no-index -f /wheelhouse -r requirements.txt
WORKDIR /var/run/flaskbb-scripts
COPY ./scripts .
RUN pip install --no-index -f /wheelhouse -r requirements.txt && \
    rm -rf /wheelhouse
RUN flaskbb translations compile
WORKDIR /
EXPOSE 8080
ENTRYPOINT ["/var/run/flaskbb-scripts/launch"]
CMD ["uwsgi"]
