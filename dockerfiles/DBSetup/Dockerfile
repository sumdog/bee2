FROM python:3

WORKDIR /usr/src/app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY dbsetup.py .
RUN chmod 700 dbsetup.py
CMD [ "python", "./dbsetup.py" ]
