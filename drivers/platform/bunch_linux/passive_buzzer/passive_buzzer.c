#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/pwm.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "passive-buzzer"
#define DEFAULT_FREQUENCY 2000  // 2kHz - tono medio

struct buzzer_dev {
    struct pwm_device *pwm;
    struct cdev cdev;
    unsigned int frequency;
    bool enabled;
};

static dev_t buzzer_devt;
static struct class *buzzer_class;
static struct buzzer_dev *buzzer;

static int buzzer_set_frequency(struct buzzer_dev *dev, unsigned int freq)
{
    unsigned long period_ns;
    unsigned long duty_ns;
    int ret;

    if (freq == 0) {
        pwm_disable(dev->pwm);
        dev->enabled = false;
        return 0;
    }

    // Calcola periodo in nanosecondi: periodo = 1/freq
    period_ns = 1000000000UL / freq;
    
    // Duty cycle 50% per onda quadra
    duty_ns = period_ns / 2;

    ret = pwm_config(dev->pwm, duty_ns, period_ns);
    if (ret)
        return ret;

    if (!dev->enabled) {
        ret = pwm_enable(dev->pwm);
        if (ret)
            return ret;
        dev->enabled = true;
    }

    dev->frequency = freq;
    return 0;
}

static int buzzer_open(struct inode *inode, struct file *file)
{
    file->private_data = buzzer;
    return 0;
}

static ssize_t buzzer_write(struct file *file, const char __user *buf,
                           size_t count, loff_t *ppos)
{
    char kbuf[16];
    struct buzzer_dev *dev = file->private_data;
    unsigned int freq;
    int ret;

    if (count >= sizeof(kbuf))
        count = sizeof(kbuf) - 1;

    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;

    kbuf[count] = '\0';

    // Parse input
    if (kbuf[0] == '0') {
        // '0' = spegni
        ret = buzzer_set_frequency(dev, 0);
    } else if (kbuf[0] == '1') {
        // '1' = frequenza default
        ret = buzzer_set_frequency(dev, DEFAULT_FREQUENCY);
    } else {
        // Numero = frequenza specifica (es. "440" per LA)
        ret = kstrtouint(kbuf, 10, &freq);
        if (ret)
            return ret;
        
        // Limita frequenza tra 20Hz e 20kHz
        if (freq < 20 || freq > 20000)
            return -EINVAL;
        
        ret = buzzer_set_frequency(dev, freq);
    }

    if (ret)
        return ret;

    return count;
}

static ssize_t buzzer_read(struct file *file, char __user *buf,
                          size_t count, loff_t *ppos)
{
    struct buzzer_dev *dev = file->private_data;
    char kbuf[32];
    int len;

    if (*ppos > 0)
        return 0;

    len = snprintf(kbuf, sizeof(kbuf), "%u\n", dev->frequency);
    
    if (copy_to_user(buf, kbuf, len))
        return -EFAULT;

    *ppos += len;
    return len;
}

static const struct file_operations buzzer_fops = {
    .owner = THIS_MODULE,
    .open = buzzer_open,
    .read = buzzer_read,
    .write = buzzer_write,
};

static int buzzer_probe(struct platform_device *pdev)
{
    int ret;

    buzzer = devm_kzalloc(&pdev->dev, sizeof(*buzzer), GFP_KERNEL);
    if (!buzzer)
        return -ENOMEM;

    // Ottieni PWM dal device tree
    buzzer->pwm = devm_pwm_get(&pdev->dev, NULL);
    if (IS_ERR(buzzer->pwm)) {
        dev_err(&pdev->dev, "Failed to get PWM\n");
        return PTR_ERR(buzzer->pwm);
    }

    buzzer->frequency = 0;
    buzzer->enabled = false;

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

    dev_info(&pdev->dev, "PWM Passive Buzzer driver probed successfully\n");
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
    pwm_disable(buzzer->pwm);
    device_destroy(buzzer_class, buzzer_devt);
    class_destroy(buzzer_class);
    cdev_del(&buzzer->cdev);
    unregister_chrdev_region(buzzer_devt, 1);
    dev_info(&pdev->dev, "PWM Passive Buzzer driver removed\n");
}

static const struct of_device_id buzzer_of_match[] = {
    {.compatible = "bunchlinux,passive-buzzer"},
    { }
};
MODULE_DEVICE_TABLE(of, buzzer_of_match);

static struct platform_driver buzzer_driver = {
    .driver = {
        .name = DEVICE_NAME,
        .of_match_table = buzzer_of_match,
    },
    .probe = buzzer_probe,
    .remove_new = buzzer_remove,
};

module_platform_driver(buzzer_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Wael Karman");
MODULE_DESCRIPTION("PWM Passive Buzzer driver");