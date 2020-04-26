FROM node:12
RUN yarn global add serve
ADD public site
