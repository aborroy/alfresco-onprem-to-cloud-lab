ARG SHARE_TAG
FROM quay.io/alfresco/alfresco-share:${SHARE_TAG}

USER root
ARG TOMCAT_DIR=/usr/local/tomcat

COPY addons/share/amps/ ${TOMCAT_DIR}/amps/
COPY addons/share/jars/ ${TOMCAT_DIR}/webapps/share/WEB-INF/lib/

RUN set -eux; \
  if find ${TOMCAT_DIR}/amps -maxdepth 1 -name '*.amp' | grep -q .; then \
    MMT_JAR="$(find ${TOMCAT_DIR}/alfresco-mmt -maxdepth 1 -name 'alfresco-mmt*.jar' | head -n 1)"; \
    java -jar "${MMT_JAR}" install ${TOMCAT_DIR}/amps/*.amp ${TOMCAT_DIR}/webapps/share -nobackup -force; \
  fi
