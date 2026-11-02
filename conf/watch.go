package conf

import (
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsnotify/fsnotify"
)

func (p *Conf) Watch(filePath, xDnsPath string, sDnsPath string, reload func()) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return fmt.Errorf("new watcher error: %s", err)
	}
	err = watcher.Add(filePath)
	if err != nil {
		watcher.Close()
		return fmt.Errorf("watch file error: %s", err)
	}
	if xDnsPath != "" {
		err = watcher.Add(xDnsPath)
		if err != nil {
			watcher.Close()
			return fmt.Errorf("watch dns file error: %s", err)
		}
	}
	if sDnsPath != "" {
		err = watcher.Add(sDnsPath)
		if err != nil {
			watcher.Close()
			return fmt.Errorf("watch dns file error: %s", err)
		}
	}
	go p.watch(watcher, filePath, xDnsPath, sDnsPath, reload)
	return nil
}

func (p *Conf) watch(watcher *fsnotify.Watcher, filePath, xDnsPath, sDnsPath string, reload func()) {
	defer watcher.Close()
	var pre time.Time
	var timer *time.Timer
	var pending <-chan time.Time
	var name string
	defer func() {
		if timer != nil {
			timer.Stop()
		}
	}()
	for {
		select {
		case e, ok := <-watcher.Events:
			if !ok {
				return
			}
			if e.Has(fsnotify.Chmod) || pre.Add(10*time.Second).After(time.Now()) {
				continue
			}
			pre = time.Now()
			name = e.Name
			if timer == nil {
				timer = time.NewTimer(5 * time.Second)
			} else {
				timer.Reset(5 * time.Second)
			}
			pending = timer.C
		case <-pending:
			pending = nil
			switch filepath.Base(strings.TrimSuffix(name, "~")) {
			case filepath.Base(xDnsPath), filepath.Base(sDnsPath):
				log.Println("DNS file changed, reloading...")
			default:
				log.Println("config file changed, reloading...")
			}
			if err := p.reloadFromPath(filePath, reload); err != nil {
				log.Printf("reload config error: %s", err)
				continue
			}
			log.Println("reload config success")
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			if err != nil {
				log.Printf("File watcher error: %s", err)
			}
		}
	}
}

func (p *Conf) reloadFromPath(filePath string, reload func()) error {
	if err := p.LoadFromPath(filePath); err != nil {
		return err
	}
	reload()
	return nil
}
