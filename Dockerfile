FROM nginx:alpine

RUN sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf \
		&& chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
	CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

USER nginx