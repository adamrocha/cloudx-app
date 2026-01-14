# CloudX Mock SSP (Infrastructure Interview)

This is a simplified Supply-Side Platform (SSP) service used for the Infrastructure Engineer interview. The server binary has two services in it, one is the SSP auction server and one represents a bidder who bids on auctions.


### ssp endpoints 

```bash
./server ssp [port] [bidderURL]
```

- `POST /auction`: runs an auction and returns a single winning bid
- `GET /stats`: Returns a JSON summary of total auctions processed.
- `GET /healthz`: Health check endpoint.
- `GET /debug/pprof/`: Go standard profiling tools.

### bidder endpoints

```bash
./server bidder [port]
```

- `POST /bid`: receives a bid request, most of the time responds with a bid
- `GET /debug/pprof/`: Go standard profiling tools.

## running Locally

```bash
mkdir -p bin
go build -o bin/server .

# run the bidder and ssp in separate terminals
./bin/server bidder 8092
./bin/server ssp 8091 http://localhost:8092/bid

# make a request
curl -v -X POST -d '{"id": "test-auc", "app_id": "test-app"}' 'http://localhost:8091/auction'
```

## building the docker container
```bash
docker build -f ./Dockerfile -t tmp-server:latest .

# run the bidder and ssp in separate terminals
# they won't be able to talk to each other unless you create a network first
docker network create interview
docker run --name bidder --network interview --rm -it -p 8092:8092 tmp-server:latest ./server bidder 8092
docker run --name ssp --network interview --rm -it -p 8091:8091 tmp-server:latest ./server ssp 8091 http://bidder:8092/bid

# make a request
curl -v -X POST -d '{"id": "test-auc", "app_id": "test-app"}' 'http://localhost:8091/auction'
```