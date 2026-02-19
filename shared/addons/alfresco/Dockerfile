ARG ACS_TAG
FROM quay.io/alfresco/alfresco-content-repository:${ACS_TAG}

USER root
ARG TOMCAT_DIR=/usr/local/tomcat

COPY addons/repository/amps/ ${TOMCAT_DIR}/amps/
COPY addons/repository/jars/ ${TOMCAT_DIR}/webapps/alfresco/WEB-INF/lib/

RUN set -eux; \
  if find ${TOMCAT_DIR}/amps -maxdepth 1 -name '*.amp' | grep -q .; then \
    MMT_JAR="$(find ${TOMCAT_DIR}/alfresco-mmt -maxdepth 1 -name 'alfresco-mmt*.jar' | head -n 1)"; \
    java -jar "${MMT_JAR}" install ${TOMCAT_DIR}/amps/*.amp ${TOMCAT_DIR}/webapps/alfresco -nobackup -force; \
  fi
