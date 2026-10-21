import {parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {bindCommittedReviewImageResources} from "../committed-review-images";

const first = "data:image/png;base64,AAAA";
const second = "data:image/png;base64,AQID";

function fixture(markup: string) {
  return parseHTML(`<html><body><main>${markup}</main></body></html>`).document.querySelector("main")!;
}

describe("committed Review raster catalog binding", () => {
  it("uses the native-decoded catalog key exactly once and retains authored activation targets", () => {
    const root = fixture('<img class="scholium-embedded-image" data-scholium-image-target="Attachments/a%2525&amp;b.png" data-scholium-image-resource="Attachments/a%25&amp;b.png" alt="Authored 图">'
      + '<img class="scholium-embedded-image" data-scholium-image-resource="Attachments/a&amp;amp;b.png">');
    const [percent, entity] = root.querySelectorAll<HTMLImageElement>("img");
    expect(bindCommittedReviewImageResources(root, {"Attachments/a%25&b.png": first,
      "Attachments/a&amp;b.png": second})).toEqual([percent, entity]);
    expect(percent.getAttribute("src")).toBe(first);
    expect(entity.getAttribute("src")).toBe(second);
    expect(percent.dataset.scholiumImageTarget).toBe("Attachments/a%2525&b.png");
    expect(percent.alt).toBe("Authored 图");
  });

  it("updates and removes only owned raster src without replacing text, images or link containers", () => {
    const root = fixture('<p>Selected text <a href="scholium-note:Other"><img class="scholium-embedded-image" data-scholium-image-resource="a.png"></a></p>'
      + '<img class="scholium-embedded-image" data-scholium-image-resource="missing.png">'
      + '<img class="ordinary-image" data-scholium-image-resource="a.png" src="data:image/png;base64,AQID">');
    const paragraph = root.querySelector("p")!, text = paragraph.firstChild;
    const linked = root.querySelector("a")!, image = linked.querySelector("img")!;
    const missing = root.querySelectorAll("img")[1], ordinary = root.querySelectorAll("img")[2];
    expect(bindCommittedReviewImageResources(root, {"a.png": first})).toEqual([image]);
    image.style.setProperty("--scholium-image-aspect-ratio", "2");
    expect(bindCommittedReviewImageResources(root, {"a.png": first})).toEqual([]);
    expect(image.style.getPropertyValue("--scholium-image-aspect-ratio")).toBe("2");
    expect(bindCommittedReviewImageResources(root, {"a.png": second})).toEqual([image]);
    expect(image.getAttribute("src")).toBe(second);
    expect(image.style.getPropertyValue("--scholium-image-aspect-ratio")).toBe("");
    expect(bindCommittedReviewImageResources(root, {})).toEqual([image]);
    expect(image.hasAttribute("src")).toBe(false);
    expect(missing.hasAttribute("src")).toBe(false);
    expect(ordinary.getAttribute("src")).toBe(second);
    expect(root.querySelector("p")).toBe(paragraph);
    expect(paragraph.firstChild).toBe(text);
    expect(root.querySelector("a")).toBe(linked);
    expect(linked.querySelector("img")).toBe(image);
  });

  it("never reads inherited prototype resources and treats own dangerous-looking keys as inert filenames", () => {
    const root = fixture('<img class="scholium-embedded-image" data-scholium-image-resource="inherited.png">'
      + '<img class="scholium-embedded-image" data-scholium-image-resource="__proto__">'
      + '<img class="scholium-embedded-image" data-scholium-image-resource="constructor">');
    const resources: Record<string, string> = Object.assign(Object.create({"inherited.png": first}),
      JSON.parse(`{"__proto__":"${first}","constructor":"${second}"}`));
    // Assignment to __proto__ on an ordinary object would mutate its prototype.
    // Native JSON dictionary parsing supplies an own data property instead.
    Object.defineProperty(resources, "__proto__", {value: first, enumerable: true});
    const [inherited, prototype, constructor] = root.querySelectorAll("img");
    expect(bindCommittedReviewImageResources(root, resources)).toEqual([prototype, constructor]);
    expect(inherited.hasAttribute("src")).toBe(false);
    expect(prototype.getAttribute("src")).toBe(first);
    expect(constructor.getAttribute("src")).toBe(second);
    expect(Object.getPrototypeOf(resources)["inherited.png"]).toBe(first);
  });

  it("keeps the incoming HTML independent of resource size and repeated image references", () => {
    const markup = Array.from({length: 52}, (_, index) => `<img class="scholium-embedded-image" data-scholium-image-resource="a.png" alt="${index}">`).join("");
    const resource = `data:image/png;base64,${"AAAA".repeat(131_072)}`;
    const root = fixture(markup);
    expect(markup.length).toBeLessThan(6_000);
    expect(markup).not.toContain("base64");
    expect(bindCommittedReviewImageResources(root, {"a.png": resource})).toHaveLength(52);
    expect(Array.from(root.querySelectorAll("img"), image => image.getAttribute("src")))
      .toEqual(Array(52).fill(resource));
    expect(markup).not.toContain(resource);
  });

  it("binds nested annotation template fragments, preserving nodes across resource replacement and removal", () => {
    const root = fixture("");
    const document = root.ownerDocument;
    const annotation = document.createElement("template");
    const nested = document.createElement("template");
    const image = document.createElement("img");
    image.className = "scholium-embedded-image";
    image.dataset.scholiumImageResource = "a.png";
    // Build real inert fragments explicitly: linkedom's HTML parser also
    // exposes template markup as children, unlike a browser.
    nested.content.append(image);
    annotation.content.append(nested);
    root.append(annotation);
    expect(root.querySelector("img")).toBeNull();
    expect(bindCommittedReviewImageResources(root, {"a.png": first})).toEqual([image]);
    expect(image.getAttribute("src")).toBe(first);
    expect(bindCommittedReviewImageResources(root, {"a.png": second})).toEqual([image]);
    expect(image.getAttribute("src")).toBe(second);
    expect(bindCommittedReviewImageResources(root, {})).toEqual([image]);
    expect(image.hasAttribute("src")).toBe(false);
    expect(nested.content.firstChild).toBe(image);
    expect(annotation.content.firstChild).toBe(nested);
  });

  it("never binds current-document keys inside peer Embedded Notes or their template fragments", () => {
    const root = fixture('<section class="scholium-embedded-note"><img class="scholium-embedded-image" data-scholium-image-resource="a.png" src="data:image/png;base64,AQID"></section>');
    const peer = root.querySelector("section")!;
    const ordinary = peer.querySelector("img")!;
    const annotation = root.ownerDocument.createElement("template");
    const nested = root.ownerDocument.createElement("img");
    nested.className = "scholium-embedded-image";
    nested.dataset.scholiumImageResource = "a.png";
    annotation.content.append(nested);
    peer.append(annotation);
    expect(bindCommittedReviewImageResources(root, {"a.png": first})).toEqual([]);
    expect(ordinary.getAttribute("src")).toBe(second);
    expect(nested.hasAttribute("src")).toBe(false);
    expect(bindCommittedReviewImageResources(root, {})).toEqual([]);
    expect(ordinary.getAttribute("src")).toBe(second);
  });
});
