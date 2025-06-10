# =========================================================================
# STAGE 1: Reference the CloudSaver image
# =========================================================================
FROM jiangrui1994/cloudsaver:latest AS cloudsaver_stage

# =========================================================================
# STAGE 2: Main build stage for the fat image (FINAL SHOWSTOPPER FIX)
# =========================================================================
FROM ubuntu:22.04

# --- Environment and Arguments ---
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# --- 1. Install Base Packages & Dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common git openssh-server sudo curl wget cron nano tar gzip unzip sshpass \
    python3 python3-pip python3-dev build-essential \
    apache2 supervisor mysql-server && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Install Go Language Environment ---
RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# --- 3. Install Node.js Environment (LTS) ---
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --- 4. Install PHP 7.4 and Extensions ---
RUN add-apt-repository ppa:ondrej/php -y && apt-get update && \
    apt-get install -y --no-install-recommends \
    php7.4 php7.4-mysql php7.4-gd php7.4-curl php7.4-mbstring php7.4-xml php7.4-zip \
    php7.4-bcmath php7.4-soap php7.4-intl php7.4-readline libapache2-mod-php7.4 && \
    rm -rf /var/lib/apt/lists/*

# --- 5. Integrate CloudSaver (FINAL FIX: Rebuild native modules) ---
COPY --from=cloudsaver_stage /app /opt/cloudsaver/
# Remove the incompatible Alpine-compiled modules and rebuild them on Ubuntu
RUN cd /opt/cloudsaver && \
    rm -rf node_modules && \
    npm install --omit=dev

# --- 6. Configure Services ---
COPY supervisord.conf /etc/supervisor/supervisord.conf
RUN mkdir -p /var/log/supervisor

# --- 6.1 Configure Apache ---
RUN a2enmod rewrite proxy proxy_http headers
COPY apache-maccms.conf /etc/apache2/sites-available/000-default.conf
COPY maccms-htaccess.txt /maccms-htaccess.txt
RUN mkdir -p /var/www/html/maccms && \
    chown -R www-data:www-data /var/www/html && \
    echo "ServerName localhost" >> /etc/apache2/apache2.conf

# --- FIX for SSH Password Login ---
RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# --- Configure MySQL ---
RUN sed -i 's|datadir\s*=\s*/var/lib/mysql|datadir = /var/www/html/mysql_data|' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|#bind-address\s*=\s*127.0.0.1|bind-address = 127.0.0.1|' /etc/mysql/mysql.conf.d/mysqld.cnf

# --- 7. Setup Scripts and Entrypoint ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- 8. Final Steps ---
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
