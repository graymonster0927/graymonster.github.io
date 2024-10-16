# 使用官方的 Ruby 镜像
FROM docker.m.daocloud.io/library/ruby:3.2.0

ARG ENVIRONMENT

# 设置工作目录
WORKDIR /usr/src/app/blog/

# 复制 Gemfile 和 Gemfile.lock 到容器中
COPY blog /usr/src/app/blog/
RUN if [ "$ENVIRONMENT" = "local" ]; then \
      RUN sed -i 's/source "https://rubygems.org/"/source "https://gems.ruby-china.com"/' /Gemfile; \
      RUN apt-get update && apt-get install -y vim; \
      RUN gem sources --add https://gems.ruby-china.com/ --remove https://rubygems.org/ && bundle install

    else \
      RUN bundle install

    fi \

# 公开端口
EXPOSE 4000

# 启动 Jekyll 服务
CMD ["bundle", "exec", "jekyll", "serve", "--host=0.0.0.0"]

