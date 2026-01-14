package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync/atomic"

	"github.com/google/uuid"
)

func RunSSP(port string, bidderURL string) {
	bindaddr := ":" + port
	log.Printf("CloudX Mock SSP starting on %s...", bindaddr)

	mux := http.NewServeMux()
	srv := NewSSP(bidderURL)
	srv.Mount(mux)
	http.Handle("/", mux)

	server := &http.Server{
		Addr:    bindaddr,
		Handler: http.DefaultServeMux,
	}

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed: %s", err)
	}
	os.Exit(0)
}

func NewSSP(bidderURL string) *SSP {
	return &SSP{
		bidderURL: bidderURL,
	}
}

type SSP struct {
	auctionCount uint64
	bidderURL    string
}

func (s *SSP) Mount(mux *http.ServeMux) {
	mux.HandleFunc("POST /auction", s.Auction)
	mux.HandleFunc("GET /stats", s.Stats)
	mux.HandleFunc("GET /healthz", s.Healthz)
}

// Endpoint for /auction
func (s *SSP) Auction(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&s.auctionCount, 1)

	var ar AuctionRequest
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(&ar); err != nil {
		http.Error(w, fmt.Sprintf("invalid request: %s", err), http.StatusBadRequest)
		return
	}

	bidReq := &BidRequest{
		AppID:     ar.AppID,
		AuctionID: "au_" + uuid.NewString(),
		BidID:     "bid_" + uuid.NewString(),
		SSP:       "cloudx",
	}

	bid, err := getBid(s.bidderURL, bidReq)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to fetch bid: %s", err), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	auctionResult := AuctionResult{
		AuctionID: ar.ID,
	}
	if bid != nil {
		auctionResult.WinningBid = &WinningBid{
			BidID: bid.BidID,
			Price: bid.Price,
		}
	}
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(auctionResult); err != nil {
		panic(err)
	}
}

func getBid(bidderURL string, ar *BidRequest) (*BidResponse, error) {
	body, err := json.Marshal(ar)
	if err != nil {
		return nil, err
	}
	netResp, err := http.Post(
		bidderURL,
		"application/json",
		bytes.NewReader(body),
	)
	if err != nil {
		return nil, err
	}
	if netResp.StatusCode == http.StatusNoContent {
		return nil, nil
	}
	var bidResp BidResponse
	err = json.NewDecoder(netResp.Body).Decode(&bidResp)
	if err != nil {
		return nil, err
	}
	return &bidResp, nil
}

// Endpoint for /stats
func (s *SSP) Stats(w http.ResponseWriter, r *http.Request) {
	count := atomic.LoadUint64(&s.auctionCount)
	w.Header().Set("Content-Type", "application/json")
	_, _ = fmt.Fprintf(w, `{"total_auctions": %d}`, count)
}

// Endpoint for /healthz
func (s *SSP) Healthz(w http.ResponseWriter, r *http.Request) {
	_, _ = fmt.Fprint(w, "OK")
}
