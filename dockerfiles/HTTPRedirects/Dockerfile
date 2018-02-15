FROM python:3

WORKDIR /usr/src/app

#COPY requirements.txt ./
#RUN pip install --no-cache-dir -r requirements.txt

COPY redirect-server.py .
RUN chmod 700 redirect-server.py
CMD [ "python", "./redirect-server.py" ]
