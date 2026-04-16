FROM apache/nifi:1.24.0

USER root

ADD https://jdbc.postgresql.org/download/postgresql-42.7.3.jar /opt/nifi/nifi-current/lib/

RUN chown nifi:nifi /opt/nifi/nifi-current/lib/postgresql-42.7.3.jar

USER nifi