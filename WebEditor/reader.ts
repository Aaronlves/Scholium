import {initializeReader, type ReaderWindow} from "./reader-runtime";

const readerWindow = window as ReaderWindow;
readerWindow.scholiumRead = {
  initialize(value: unknown) {
    const ready = initializeReader(value);
    readerWindow.scholiumReadReady = ready;
    return ready;
  },
};
