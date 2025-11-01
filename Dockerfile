# Use the official Debian 11 image as a parent image
FROM debian:11

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Update the package lists and install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user and group
RUN groupadd -r ysfreflector && useradd -r -g ysfreflector ysfreflector

# Set the working directory
WORKDIR /opt/YSFReflector

# Copy the application files
COPY . .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Create the configuration and log directories and set permissions
RUN mkdir -p /etc/ysfreflector /var/log/ysfreflector && \
    touch /etc/ysfreflector/deny.db && \
    chown -R ysfreflector:ysfreflector /etc/ysfreflector /var/log/ysfreflector
COPY YSFReflector.ini /etc/ysfreflector/

# Switch to the non-root user
USER ysfreflector

# Expose the reflector port
EXPOSE 42395

# Copy the entrypoint script
COPY entrypoint.sh /usr/local/bin/

# Set the entrypoint
ENTRYPOINT ["entrypoint.sh"]
CMD ["python3", "YSFReflector", "/etc/ysfreflector/YSFReflector.ini"]
