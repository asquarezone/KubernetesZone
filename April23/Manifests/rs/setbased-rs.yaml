---
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: setbased
  labels:
    purpose: understanding
    concept: setbased
spec:
  minReadySeconds: 2
  replicas: 3
  selector:
    matchExpressions:
      - key: app
        operator: In
        values:
          - nginx
          - web
      - key: env
        operator: NotIn
        values:
          - prod
          - uat
      - key: failing
        operator: DoesNotExist
        values:
  template:
    metadata:
      name: nginx
      labels:
        app: nginx
        env: dev
    spec:
      containers:
        - name: nginx
          image: nginx:1.23
          ports:
            - containerPort: 80