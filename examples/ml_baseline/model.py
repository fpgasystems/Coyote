"""Models for binary classification of grayscale bitstream images.

Available models:
  - resnet18: Grayscale ResNet-18 (11,170,753 params)
  - cnn_a:    Tiny 3-layer CNN     (6,241 params)
  - cnn_b:    Small 4-layer CNN    (60,545 params)

All models accept [B, 1, 1024, 1024] input and produce [B, 1] logits
for BCEWithLogitsLoss.
"""

import torch
import torch.nn as nn
import torchvision.models as models


# ---------------------------------------------------------------------------
# ResNet-18 (grayscale)
# ---------------------------------------------------------------------------

def grayscale_resnet18(pretrained=False):
    """Create a grayscale ResNet-18 with 1 output logit.

    Spatial shape progression for 1024x1024 input:
        Input:    [B,   1, 1024, 1024]
        conv1:    [B,  64,  512,  512]   (7x7, stride 2, pad 3)
        maxpool:  [B,  64,  256,  256]   (3x3, stride 2, pad 1)
        layer1:   [B,  64,  256,  256]
        layer2:   [B, 128,  128,  128]
        layer3:   [B, 256,   64,   64]
        layer4:   [B, 512,   32,   32]
        avgpool:  [B, 512,    1,    1]
        fc:       [B,   1]
    """
    weights = "IMAGENET1K_V1" if pretrained else None
    model = models.resnet18(weights=weights)

    old_conv1 = model.conv1
    model.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
    if pretrained:
        with torch.no_grad():
            model.conv1.weight.copy_(old_conv1.weight.mean(dim=1, keepdim=True))

    model.fc = nn.Linear(model.fc.in_features, 1)
    return model


# ---------------------------------------------------------------------------
# CNN A — Tiny CNN (6,241 params)
# ---------------------------------------------------------------------------

class TinyCNN(nn.Module):
    """3-layer CNN for binary classification of grayscale images.

    Spatial shape progression for 1024x1024 input:
        Input:           [B,  1, 1024, 1024]
        Conv2d 7x7 s4:   [B,  8,  256,  256]
        MaxPool2d 2x2:   [B,  8,  128,  128]
        Conv2d 3x3:      [B, 16,  128,  128]
        MaxPool2d 2x2:   [B, 16,   64,   64]
        Conv2d 3x3:      [B, 32,   64,   64]
        AdaptiveAvgPool: [B, 32,    1,    1]
        Linear:          [B,  1]

    Total parameters: 6,241
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 8, kernel_size=7, stride=4, padding=3),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(8, 16, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.fc = nn.Linear(32, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.fc(x)


# ---------------------------------------------------------------------------
# CNN B — Small CNN (60,545 params)
# ---------------------------------------------------------------------------

class SmallCNN(nn.Module):
    """4-layer CNN for binary classification of grayscale images.

    Spatial shape progression for 1024x1024 input:
        Input:           [B,  1, 1024, 1024]
        Conv2d 5x5 s2:   [B, 16,  512,  512]
        MaxPool2d 2x2:   [B, 16,  256,  256]
        Conv2d 3x3:      [B, 32,  256,  256]
        MaxPool2d 2x2:   [B, 32,  128,  128]
        Conv2d 3x3:      [B, 64,  128,  128]
        MaxPool2d 2x2:   [B, 64,   64,   64]
        Conv2d 3x3:      [B, 64,   64,   64]
        AdaptiveAvgPool: [B, 64,    1,    1]
        Linear:          [B,  1]

    Total parameters: 60,545
    """

    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=5, stride=2, padding=2),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(32, 64, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
            nn.Conv2d(64, 64, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1)),
        )
        self.fc = nn.Linear(64, 1)

    def forward(self, x):
        x = self.features(x)
        x = x.flatten(1)
        return self.fc(x)


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

MODEL_CHOICES = ["resnet18", "cnn_a", "cnn_b"]


def build_model(name):
    """Build a model by name. Returns an nn.Module with [B,1] output."""
    if name == "resnet18":
        return grayscale_resnet18(pretrained=False)
    elif name == "cnn_a":
        return TinyCNN()
    elif name == "cnn_b":
        return SmallCNN()
    else:
        raise ValueError(f"Unknown model: {name!r}. Choose from {MODEL_CHOICES}")


def test_forward_pass():
    """Verify all models run with a dummy 1024x1024 input."""
    x = torch.randn(2, 1, 1024, 1024)
    for name in MODEL_CHOICES:
        model = build_model(name)
        model.eval()
        with torch.no_grad():
            out = model(x)
        n_params = sum(p.numel() for p in model.parameters())
        print(f"{name:10s}: output={out.shape}  params={n_params:,}")
        assert out.shape == (2, 1), f"Expected (2, 1), got {out.shape}"
    print("All forward passes OK")


if __name__ == "__main__":
    test_forward_pass()
