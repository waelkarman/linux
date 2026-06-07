#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/gpio/consumer.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "active-buzzer"

struct buzzer_dev {
    struct gpio_desc *gpio;
    struct cdev cdev;
};

static dev_t buzzer_devt;
static struct class *buzzer_class;
static struct buzzer_dev *buzzer;

static int buzzer_open(struct inode *inode, struct file *file)
{
    file->private_data = buzzer;
    return 0;
}

static ssize_t buzzer_write(struct file *file, const char __user *buf,
                            size_t count, loff_t *ppos)
{
    char kbuf;
    struct buzzer_dev *dev = file->private_data;

    if (copy_from_user(&kbuf, buf, 1))
        return -EFAULT;

    if (kbuf == '1')
        gpiod_set_value(dev->gpio, 1);
    else
        gpiod_set_value(dev->gpio, 0);

    return count;
}

static const struct file_operations buzzer_fops = {
    .owner = THIS_MODULE,
    .open = buzzer_open,
    .write = buzzer_write,
};

static int buzzer_probe(struct platform_device *pdev)
{
    int ret;

    buzzer = devm_kzalloc(&pdev->dev, sizeof(*buzzer), GFP_KERNEL);
    if (!buzzer)
        return -ENOMEM;

    // FIX: usa NULL invece di "gpios"
    buzzer->gpio = devm_gpiod_get(&pdev->dev, NULL, GPIOD_OUT_LOW);
    if (IS_ERR(buzzer->gpio)) {
        dev_err(&pdev->dev, "Failed to get GPIO from DT\n");
        return PTR_ERR(buzzer->gpio);
    }

    ret = alloc_chrdev_region(&buzzer_devt, 0, 1, DEVICE_NAME);
    if (ret)
        return ret;

    cdev_init(&buzzer->cdev, &buzzer_fops);
    buzzer->cdev.owner = THIS_MODULE;
    ret = cdev_add(&buzzer->cdev, buzzer_devt, 1);
    if (ret)
        goto unregister_chrdev;

    buzzer_class = class_create(DEVICE_NAME);
    if (IS_ERR(buzzer_class)) {
        ret = PTR_ERR(buzzer_class);
        goto del_cdev;
    }

    if (IS_ERR(device_create(buzzer_class, NULL, buzzer_devt, NULL, DEVICE_NAME))) {
        ret = -EINVAL;
        goto destroy_class;
    }

    dev_info(&pdev->dev, "Buzzer driver probed successfully!\n");
    return 0;

destroy_class:
    class_destroy(buzzer_class);
del_cdev:
    cdev_del(&buzzer->cdev);
unregister_chrdev:
    unregister_chrdev_region(buzzer_devt, 1);
    return ret;
}

static void buzzer_remove(struct platform_device *pdev)
{
    device_destroy(buzzer_class, buzzer_devt);
    class_destroy(buzzer_class);
    cdev_del(&buzzer->cdev);
    unregister_chrdev_region(buzzer_devt, 1);
    dev_info(&pdev->dev, "Buzzer driver removed\n");
}

static const struct of_device_id buzzer_of_match[] = {
    {.compatible = "bunchlinux,active-buzzer"},
    { }
};
MODULE_DEVICE_TABLE(of, buzzer_of_match);

static struct platform_driver buzzer_driver = {
    .driver = {
        .name = DEVICE_NAME,
        .of_match_table = buzzer_of_match,
    },
    .probe = buzzer_probe,
    .remove_new = buzzer_remove,  // Nota: kernel 6.12 usa remove_new
};

module_platform_driver(buzzer_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Wael Karman");
MODULE_DESCRIPTION("GPIO Buzzer driver for kernel 6.12");