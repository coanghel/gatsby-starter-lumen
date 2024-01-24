FROM node:lts AS development

ENV CI=true
ENV PORT=3000

WORKDIR /code
COPY package.json /code/package.json
COPY package-lock.json /code/package-lock.json
RUN npm ci
COPY . /code

CMD ["npm", "start"]

FROM development AS build
RUN npm run build

FROM nginx:alpine AS production
RUN rm /etc/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /code/public /var/www
CMD [ "nginx", "-g", "daemon off;" ]
