FROM node:current-alpine AS build

WORKDIR /app
COPY . .

RUN yarn
RUN yarn build

FROM nginx:alpine AS deplopy

WORKDIR /usr/share/nginx/html
RUN rm -rf ./
RUN rm /etc/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/public .

ENTRYPOINT [ "nginx", "-g", "daemon off;" ]
