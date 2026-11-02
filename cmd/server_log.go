package cmd

import (
	"os"

	log "github.com/sirupsen/logrus"
)

func configureLogOutput(path string) func() {
	if path == "" {
		return func() {}
	}

	previousOutput := log.StandardLogger().Out
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.SetOutput(os.Stdout)
		log.WithField("err", err).Error("Open log file failed, using stdout instead")
		return func() { log.SetOutput(previousOutput) }
	}

	log.SetOutput(f)
	return func() {
		log.SetOutput(previousOutput)
		if err := f.Close(); err != nil {
			log.WithField("err", err).Error("Close log file failed")
		}
	}
}
