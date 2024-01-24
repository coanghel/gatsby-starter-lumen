FROM gatsbyjs/gatsby:latest as build

FROM gatsbyjs/gatsby
COPY --from=build /app/public /pub
COPY nginx.conf /etc/nginx/server.conf
